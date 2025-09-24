#!/usr/bin/env python3
"""
PhoenixGuard Cooperative Cloud API Endpoints
===========================================

REST API endpoints to integrate PhoenixGuard with your cooperative cloud platform.
Handles task distribution, credit management, and browser-based contributions.

Integrates with:
- Your existing Flask/FastAPI cloud platform
- Redis for task queues and user sessions
- Tailscale VPN multi-tenant isolation
- Credit/billing system
"""

from flask import Flask, request, jsonify, session
from flask_cors import CORS
from datetime import datetime, timedelta
import json
import redis
import hashlib
import uuid
from typing import Dict, List, Optional
import logging
from cooperative_phoenixguard import CooperativePhoenixGuard, CooperativeTask

# Initialize Flask app for integration
app = Flask(__name__)
app.secret_key = "phoenixguard_cooperative_secret_key_change_in_production"
CORS(app, origins=["https://*.yourcloudplatform.com", "https://phoenixguard.coop"])

# Redis connection for your cloud platform
redis_client = redis.Redis(host='localhost', port=6379, db=1, decode_responses=True)
phoenix_coop = CooperativePhoenixGuard(redis_client)

# Logging setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ===== AUTHENTICATION & USER MANAGEMENT =====

def get_current_user():
    """Get current user from session/token"""
    # This would integrate with your existing auth system
    user_id = session.get('user_id') or request.headers.get('X-User-ID')
    if not user_id:
        # For demo, create anonymous user
        user_id = f"anon_{hashlib.md5(str(request.remote_addr).encode()).hexdigest()[:8]}"
    return user_id

def verify_user_permissions(user_id: str, required_tier: str = "Bronze") -> bool:
    """Check if user has required permissions for PhoenixGuard tasks"""
    if user_id not in phoenix_coop.contributors:
        return False
    
    tier_levels = {"Bronze": 0, "Silver": 1, "Gold": 2, "Platinum": 3, "Saint": 4}
    user_tier = phoenix_coop.get_contributor_tier(user_id).split(" ")[-1]  # Remove emoji
    
    return tier_levels.get(user_tier, 0) >= tier_levels.get(required_tier, 0)

# ===== TASK MANAGEMENT ENDPOINTS =====

@app.route('/api/phoenixguard/available-tasks', methods=['GET'])
def get_available_tasks():
    """Get tasks available for the current user"""
    user_id = get_current_user()
    
    try:
        # Get tasks suitable for user's capabilities
        user_capabilities = request.args.get('capabilities', '{}')
        capabilities = json.loads(user_capabilities) if user_capabilities != '{}' else {}
        
        # Filter tasks based on user capabilities and tier
        available_tasks = []
        for task in phoenix_coop.active_tasks.values():
            if task.status != "pending":
                continue
                
            # Check if user can handle the task
            if capabilities.get('browser') and task.task_type in ["hardware_scrape", "uefi_analysis"]:
                task_package = phoenix_coop.generate_browser_task_package(task)
                if task_package.get('type') != 'unsupported_in_browser':
                    available_tasks.append(task_package)
            elif not capabilities.get('browser') and task.task_type == "bios_generation":
                # Full system tasks
                if verify_user_permissions(user_id, "Silver"):
                    available_tasks.append({
                        "task_id": task.task_id,
                        "type": "system_task",
                        "description": task.description,
                        "credits": task.credits_reward,
                        "estimated_minutes": task.estimated_duration,
                        "requirements": task.resource_requirements
                    })
        
        # Global stats
        dashboard_data = phoenix_coop.create_cooperative_dashboard_data()
        
        return jsonify({
            "available_tasks": available_tasks,
            "user_tier": phoenix_coop.get_contributor_tier(user_id),
            "hardware_configs_liberated": dashboard_data['mission_status']['hardware_configurations_liberated'],
            "total_configs": dashboard_data['mission_status']['hardware_configurations_liberated'],
            "vendors_analyzed": dashboard_data['mission_status']['vendors_analyzed'],
            "active_contributors": dashboard_data['community_stats']['active_contributors_7d'],
            "liberation_progress": dashboard_data['liberation_progress']['percentage_complete']
        })
        
    except Exception as e:
        logger.error(f"Error getting available tasks: {e}")
        return jsonify({"error": "Failed to load tasks"}), 500

@app.route('/api/phoenixguard/claim-task', methods=['POST'])
def claim_task():
    """Claim a task for execution"""
    user_id = get_current_user()
    
    try:
        data = request.get_json()
        capabilities = data.get('capabilities', {})
        
        # Register user if not exists
        if user_id not in phoenix_coop.contributors:
            phoenix_coop.register_contributor(user_id, capabilities)
        
        # Find best matching task
        best_task = None
        for task in phoenix_coop.active_tasks.values():
            if task.status != "pending":
                continue
                
            # Match task to user capabilities
            if capabilities.get('browser'):
                if task.task_type in ["hardware_scrape", "uefi_analysis"]:
                    # Check GPU requirements for analysis tasks
                    if task.task_type == "uefi_analysis" and not capabilities.get('webgl'):
                        continue
                    best_task = task
                    break
            else:
                # System tasks for dedicated workers
                if verify_user_permissions(user_id, "Silver"):
                    best_task = task
                    break
        
        if not best_task:
            return jsonify({"message": "No suitable tasks available"}), 404
        
        # Claim the task
        best_task.status = "claimed"
        
        # Store task assignment in Redis
        redis_client.hset(
            f"phoenixguard:claimed_tasks:{user_id}",
            best_task.task_id,
            json.dumps({
                "claimed_at": datetime.now().isoformat(),
                "task_data": best_task.__dict__
            })
        )
        
        # Generate appropriate task package
        if capabilities.get('browser'):
            task_package = phoenix_coop.generate_browser_task_package(best_task)
        else:
            task_package = {
                "task_id": best_task.task_id,
                "type": "system_task",
                "description": best_task.description,
                "credits": best_task.credits_reward,
                "data_payload": best_task.data_payload,
                "requirements": best_task.resource_requirements
            }
        
        logger.info(f"Task {best_task.task_id} claimed by user {user_id}")
        return jsonify(task_package)
        
    except Exception as e:
        logger.error(f"Error claiming task: {e}")
        return jsonify({"error": "Failed to claim task"}), 500

@app.route('/api/phoenixguard/submit-task/<task_id>', methods=['POST'])
def submit_task_results(task_id: str):
    """Submit completed task results"""
    user_id = get_current_user()
    
    try:
        data = request.get_json()
        
        # Verify task was claimed by this user
        claimed_task_data = redis_client.hget(f"phoenixguard:claimed_tasks:{user_id}", task_id)
        if not claimed_task_data:
            return jsonify({"error": "Task not found or not claimed by user"}), 404
        
        task_info = json.loads(claimed_task_data)
        task = phoenix_coop.active_tasks.get(task_id)
        
        if not task:
            return jsonify({"error": "Task no longer exists"}), 404
        
        # Validate results and calculate quality score
        quality_score = calculate_task_quality(task, data)
        
        # Update task status
        task.status = "completed" if quality_score >= 0.5 else "failed"
        
        # Award credits
        credits_awarded = phoenix_coop.award_credits(
            user_id, 
            task.credits_reward, 
            task.task_type,
            quality_score
        )
        
        # Convert to cloud credits
        cloud_credits = phoenix_coop.integrate_with_cloud_credits(user_id, credits_awarded)
        
        # Store results
        redis_client.hset(
            f"phoenixguard:task_results:{task_id}",
            mapping={
                "user_id": user_id,
                "submitted_at": datetime.now().isoformat(),
                "results": json.dumps(data),
                "quality_score": quality_score,
                "credits_awarded": credits_awarded,
                "status": task.status
            }
        )
        
        # Clean up claimed task
        redis_client.hdel(f"phoenixguard:claimed_tasks:{user_id}", task_id)
        
        # Update user's cloud credits in your platform
        update_user_cloud_credits(user_id, cloud_credits)
        
        logger.info(f"Task {task_id} completed by {user_id} with quality {quality_score:.2f}")
        
        return jsonify({
            "status": "success",
            "credits_awarded": credits_awarded,
            "cloud_credits": cloud_credits,
            "quality_score": quality_score,
            "new_tier": phoenix_coop.get_contributor_tier(user_id),
            "message": f"🎉 Great work! Earned {credits_awarded} credits!"
        })
        
    except Exception as e:
        logger.error(f"Error submitting task results: {e}")
        return jsonify({"error": "Failed to submit results"}), 500

def calculate_task_quality(task: CooperativeTask, results: Dict) -> float:
    """Calculate quality score for task submission"""
    base_score = 0.8  # Default good score
    
    try:
        if task.task_type == "hardware_scrape":
            # Check number of configurations found
            configs_found = len(results.get('hardware_configs', []))
            expected = task.data_payload.get('expected_configs', 20)
            
            if configs_found >= expected:
                return min(1.0, base_score + 0.2)
            elif configs_found >= expected * 0.7:
                return base_score
            else:
                return max(0.3, base_score - 0.3)
                
        elif task.task_type == "uefi_analysis":
            # Check analysis completeness
            patterns_found = results.get('patterns_found', 0)
            processing_time = results.get('processing_time_ms', 0)
            
            if patterns_found >= 20 and processing_time > 0:
                return min(1.0, base_score + 0.15)
            elif patterns_found >= 10:
                return base_score
            else:
                return max(0.4, base_score - 0.2)
                
        elif task.task_type == "bios_generation":
            # Check if BIOS was successfully generated
            if results.get('bios_generated') and results.get('verification_passed'):
                return 1.0
            elif results.get('bios_generated'):
                return 0.8
            else:
                return 0.3
                
    except Exception as e:
        logger.warning(f"Error calculating quality score: {e}")
    
    return base_score

# ===== USER DASHBOARD ENDPOINTS =====

@app.route('/api/phoenixguard/user/profile', methods=['GET'])
def get_user_profile():
    """Get user's PhoenixGuard profile and stats"""
    user_id = get_current_user()
    
    if user_id not in phoenix_coop.contributors:
        return jsonify({"message": "User not registered"}), 404
    
    contributor = phoenix_coop.contributors[user_id]
    
    # Get recent task history
    recent_tasks = []
    for task_id in redis_client.hkeys(f"phoenixguard:task_results:*"):
        result_data = redis_client.hgetall(task_id)
        if result_data.get('user_id') == user_id:
            recent_tasks.append({
                "task_id": task_id.split(':')[-1],
                "completed_at": result_data.get('submitted_at'),
                "credits_earned": int(result_data.get('credits_awarded', 0)),
                "quality_score": float(result_data.get('quality_score', 0))
            })
    
    recent_tasks = sorted(recent_tasks, key=lambda x: x['completed_at'], reverse=True)[:10]
    
    profile_data = {
        "user_id": user_id,
        "tier": phoenix_coop.get_contributor_tier(user_id),
        "total_credits": contributor['total_credits_earned'],
        "tasks_completed": contributor['tasks_completed'], 
        "tasks_failed": contributor['tasks_failed'],
        "reputation_score": contributor['reputation_score'],
        "specializations": contributor['specializations'],
        "registered_at": contributor['registered_at'],
        "recent_tasks": recent_tasks,
        
        # Achievement progress
        "achievements": {
            "next_tier_credits": get_next_tier_requirement(contributor['total_credits_earned']),
            "hardware_liberation_badge": contributor['tasks_completed'] >= 10,
            "gpu_computing_expert": "gpu_computing" in contributor['specializations'] and contributor['tasks_completed'] >= 5,
            "community_hero": contributor['total_credits_earned'] >= 500,
            "firmware_saint": contributor['total_credits_earned'] >= 1000
        }
    }
    
    return jsonify(profile_data)

def get_next_tier_requirement(current_credits: int) -> Dict:
    """Get requirements for next tier"""
    tiers = [
        ("🥉 Bronze", 0),
        ("🥈 Silver", 25),
        ("🥇 Gold", 100),
        ("💎 Platinum", 500),
        ("👼 Saint", 1000)
    ]
    
    for tier_name, required_credits in tiers:
        if current_credits < required_credits:
            return {
                "tier": tier_name,
                "credits_needed": required_credits - current_credits,
                "credits_required": required_credits
            }
    
    return {"tier": "👼 Saint", "credits_needed": 0, "credits_required": 1000}

# ===== GLOBAL DASHBOARD ENDPOINTS =====

@app.route('/api/phoenixguard/dashboard', methods=['GET'])
def get_global_dashboard():
    """Get global PhoenixGuard liberation dashboard"""
    dashboard_data = phoenix_coop.create_cooperative_dashboard_data()
    
    # Add real-time statistics
    dashboard_data["realtime_stats"] = {
        "tasks_completed_today": get_daily_task_count(),
        "credits_awarded_today": get_daily_credits(),
        "new_contributors_today": get_daily_new_users(),
        "hardware_configs_today": get_daily_hardware_discoveries()
    }
    
    # Add leaderboard
    dashboard_data["leaderboard"] = get_contributor_leaderboard()
    
    return jsonify(dashboard_data)

def get_daily_task_count() -> int:
    """Get tasks completed today"""
    today = datetime.now().strftime('%Y-%m-%d')
    return len([k for k in redis_client.keys(f"phoenixguard:task_results:*") 
               if redis_client.hget(k, 'submitted_at', '').startswith(today)])

def get_daily_credits() -> int:
    """Get credits awarded today"""
    today = datetime.now().strftime('%Y-%m-%d')
    total = 0
    for key in redis_client.keys(f"phoenixguard:task_results:*"):
        result = redis_client.hgetall(key)
        if result.get('submitted_at', '').startswith(today):
            total += int(result.get('credits_awarded', 0))
    return total

def get_daily_new_users() -> int:
    """Get new contributors today"""
    today = datetime.now().strftime('%Y-%m-%d')
    return len([c for c in phoenix_coop.contributors.values() 
               if c['registered_at'].startswith(today)])

def get_daily_hardware_discoveries() -> int:
    """Get hardware configs discovered today"""
    # This would query your actual hardware database
    return len([hw for hw in phoenix_coop.hardware_database.values() 
               if hw.get('discovered_date', '').startswith(datetime.now().strftime('%Y-%m-%d'))])

def get_contributor_leaderboard(limit: int = 10) -> List[Dict]:
    """Get top contributors leaderboard"""
    contributors = list(phoenix_coop.contributors.values())
    contributors.sort(key=lambda x: x['total_credits_earned'], reverse=True)
    
    leaderboard = []
    for i, contributor in enumerate(contributors[:limit]):
        leaderboard.append({
            "rank": i + 1,
            "user_id": contributor['user_id'][:8] + "..." if len(contributor['user_id']) > 8 else contributor['user_id'],
            "tier": phoenix_coop.get_contributor_tier(contributor['user_id']),
            "credits": contributor['total_credits_earned'],
            "tasks_completed": contributor['tasks_completed'],
            "specializations": contributor['specializations']
        })
    
    return leaderboard

# ===== CLOUD PLATFORM INTEGRATION =====

def update_user_cloud_credits(user_id: str, cloud_credits: Dict):
    """Update user's cloud computing credits in your platform"""
    try:
        # This integrates with your existing billing/credits system
        for credit_type, amount in cloud_credits.items():
            redis_client.hincrbyfloat(f"cloud_credits:{user_id}", credit_type, amount)
        
        logger.info(f"Updated cloud credits for user {user_id}: {cloud_credits}")
        
    except Exception as e:
        logger.error(f"Failed to update cloud credits: {e}")

@app.route('/api/phoenixguard/convert-credits', methods=['POST'])
def convert_credits():
    """Convert PhoenixGuard credits to cloud computing credits"""
    user_id = get_current_user()
    data = request.get_json()
    
    phoenixguard_credits = data.get('phoenixguard_credits', 0)
    credit_type = data.get('credit_type', 'container_hours')
    
    if user_id not in phoenix_coop.contributors:
        return jsonify({"error": "User not registered"}), 404
    
    contributor = phoenix_coop.contributors[user_id]
    
    if contributor['total_credits_earned'] < phoenixguard_credits:
        return jsonify({"error": "Insufficient PhoenixGuard credits"}), 400
    
    # Convert credits
    cloud_credits = phoenix_coop.integrate_with_cloud_credits(user_id, phoenixguard_credits)
    
    if credit_type not in cloud_credits:
        return jsonify({"error": "Invalid credit type"}), 400
    
    # Deduct PhoenixGuard credits and add cloud credits
    contributor['total_credits_earned'] -= phoenixguard_credits
    update_user_cloud_credits(user_id, {credit_type: cloud_credits[credit_type]})
    
    return jsonify({
        "converted": phoenixguard_credits,
        "received": {credit_type: cloud_credits[credit_type]},
        "remaining_phoenixguard_credits": contributor['total_credits_earned']
    })

# ===== BROWSER WIDGET ENDPOINTS =====

@app.route('/api/phoenixguard/widget-data', methods=['GET'])
def get_widget_data():
    """Get data for browser contribution widget"""
    user_id = get_current_user()
    
    # Get user's contribution stats
    user_stats = {}
    if user_id in phoenix_coop.contributors:
        contributor = phoenix_coop.contributors[user_id]
        user_stats = {
            "credits_earned": contributor['total_credits_earned'],
            "tier": phoenix_coop.get_contributor_tier(user_id),
            "tasks_completed": contributor['tasks_completed']
        }
    
    # Global impact stats
    dashboard = phoenix_coop.create_cooperative_dashboard_data()
    
    widget_data = {
        "user_stats": user_stats,
        "global_impact": {
            "configs_liberated": dashboard['mission_status']['hardware_configurations_liberated'],
            "vendors_analyzed": dashboard['mission_status']['vendors_analyzed'],
            "active_contributors": dashboard['community_stats']['active_contributors_7d']
        },
        "available_browser_tasks": len([t for t in phoenix_coop.active_tasks.values() 
                                      if t.status == "pending" and t.task_type in ["hardware_scrape", "uefi_analysis"]]),
        "estimated_earnings_per_hour": 25
    }
    
    return jsonify(widget_data)

@app.route('/static/phoenixguard-widget.js')
def serve_widget_script():
    """Serve the browser contribution widget script"""
    from cooperative_phoenixguard import create_browser_contribution_widget
    
    widget_js = create_browser_contribution_widget()
    
    response = app.response_class(
        widget_js,
        mimetype='application/javascript',
        headers={
            'Cache-Control': 'public, max-age=3600',
            'Access-Control-Allow-Origin': '*'
        }
    )
    return response

# ===== WEBHOOK ENDPOINTS FOR INTEGRATION =====

@app.route('/api/phoenixguard/webhook/task-completed', methods=['POST'])
def task_completed_webhook():
    """Webhook for external task completion notifications"""
    data = request.get_json()
    
    # Verify webhook signature (implement your security)
    
    user_id = data.get('user_id')
    task_id = data.get('task_id')
    results = data.get('results', {})
    
    if not all([user_id, task_id]):
        return jsonify({"error": "Missing required fields"}), 400
    
    # Process external task completion
    task = phoenix_coop.active_tasks.get(task_id)
    if task:
        quality_score = calculate_task_quality(task, results)
        credits = phoenix_coop.award_credits(user_id, task.credits_reward, task.task_type, quality_score)
        cloud_credits = phoenix_coop.integrate_with_cloud_credits(user_id, credits)
        update_user_cloud_credits(user_id, cloud_credits)
    
    return jsonify({"status": "processed"})

# ===== HEALTH CHECK =====

@app.route('/api/phoenixguard/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    try:
        # Test Redis connection
        redis_client.ping()
        
        return jsonify({
            "status": "healthy",
            "active_tasks": len(phoenix_coop.active_tasks),
            "registered_contributors": len(phoenix_coop.contributors),
            "redis_connected": True,
            "firmware_liberation_active": True
        })
    except Exception as e:
        return jsonify({
            "status": "unhealthy",
            "error": str(e)
        }), 500

if __name__ == '__main__':
    print("🔥 PHOENIXGUARD COOPERATIVE API STARTING...")
    print("🌍 Firmware liberation meets cooperative computing!")
    print("🚀 Browser-based contribution system ready!")
    print("=" * 50)
    
    # Initialize some demo data
    phoenix_coop.create_hardware_scraping_tasks()
    phoenix_coop.create_uefi_analysis_tasks()
    phoenix_coop.create_universal_bios_tasks()
    
    app.run(host='0.0.0.0', port=8001, debug=True)
