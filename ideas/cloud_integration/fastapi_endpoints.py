#!/usr/bin/env python3
"""
PhoenixGuard Cooperative Cloud FastAPI Endpoints
===============================================

REST API endpoints to integrate PhoenixGuard with your cooperative cloud platform.
Built with FastAPI for improved performance, automatic OpenAPI docs, and async support.

Integrates with:
- Your existing cooperative cloud platform
- Redis for task queues and user sessions
- Tailscale VPN multi-tenant isolation
- Credit/billing system
"""

import asyncio
import json
import hashlib
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Union

import redis.asyncio as redis
from fastapi import FastAPI, Depends, HTTPException, Header, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, Field

from cooperative_phoenixguard import CooperativePhoenixGuard, CooperativeTask

# Initialize FastAPI
app = FastAPI(
    title="PhoenixGuard Cooperative Cloud API",
    description="API for integrating PhoenixGuard hardware liberation with cooperative cloud computing",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json"
)

# CORS setup
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://*.yourcloudplatform.com", "https://phoenixguard.coop"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Redis (async client)
redis_pool = redis.ConnectionPool(host='localhost', port=6379, db=1, decode_responses=True)
async def get_redis():
    """Get async Redis client"""
    redis_client = redis.Redis(connection_pool=redis_pool)
    try:
        yield redis_client
    finally:
        await redis_client.close()

# Initialize PhoenixGuard cooperative integration
# Note: We'll create this on-demand in the endpoints since the main class isn't async
# and we don't want to block the FastAPI server startup

# ===== PYDANTIC MODELS =====

class Capabilities(BaseModel):
    """User system capabilities"""
    browser: bool = False
    webgl: bool = False
    webworkers: bool = False
    cpu_cores: int = 2
    ram_gb: int = 4
    gpu_count: int = 0
    gpu_memory_gb: Optional[int] = None
    storage_gb: Optional[int] = None
    network_speed_mbps: Optional[int] = None

class TaskClaimRequest(BaseModel):
    """Request to claim a task"""
    capabilities: Capabilities

class CloudCreditConversion(BaseModel):
    """Request to convert PhoenixGuard credits to cloud credits"""
    phoenixguard_credits: int = Field(..., gt=0)
    credit_type: str = "container_hours"

class TaskResultsSubmission(BaseModel):
    """Task results submission"""
    results: Dict[str, Any]
    execution_time: Optional[int] = None
    
class WebhookPayload(BaseModel):
    """External webhook payload"""
    user_id: str
    task_id: str
    results: Dict[str, Any]
    signature: Optional[str] = None

# ===== AUTHENTICATION & USER MANAGEMENT =====

api_key_header = APIKeyHeader(name="X-User-ID", auto_error=False)

async def get_current_user(
    request: Request,
    x_user_id: Optional[str] = Depends(api_key_header),
    redis_client: redis.Redis = Depends(get_redis)
) -> str:
    """Get current user ID from request"""
    # This would integrate with your existing auth system
    if x_user_id:
        return x_user_id
    
    # Check if user is in session via cookie
    session_id = request.cookies.get("phoenixguard_session")
    if session_id:
        user_id = await redis_client.get(f"phoenixguard:sessions:{session_id}")
        if user_id:
            return user_id
    
    # For demo, create anonymous user from IP
    client_ip = request.client.host
    user_id = f"anon_{hashlib.md5(str(client_ip).encode()).hexdigest()[:8]}"
    
    return user_id

async def verify_user_permissions(
    user_id: str, 
    required_tier: str = "Bronze",
    redis_client: redis.Redis = Depends(get_redis)
) -> bool:
    """Check if user has required permissions for PhoenixGuard tasks"""
    # Get cooperative system and check permissions
    phoenix_coop = get_cooperative_system(redis_client)
    
    if user_id not in phoenix_coop.contributors:
        return False
    
    tier_levels = {"Bronze": 0, "Silver": 1, "Gold": 2, "Platinum": 3, "Saint": 4}
    user_tier = phoenix_coop.get_contributor_tier(user_id).split(" ")[-1]  # Remove emoji
    
    return tier_levels.get(user_tier, 0) >= tier_levels.get(required_tier, 0)

def get_cooperative_system(redis_client) -> CooperativePhoenixGuard:
    """Get or create the cooperative system instance"""
    # We're using a non-async client for the core system
    # In a real implementation, you'd want to make CooperativePhoenixGuard fully async
    sync_redis = redis.Redis.from_url(f"redis://{redis_client.connection_pool.connection_kwargs['host']}:{redis_client.connection_pool.connection_kwargs['port']}/{redis_client.connection_pool.connection_kwargs['db']}")
    
    return CooperativePhoenixGuard(sync_redis)

# ===== TASK MANAGEMENT ENDPOINTS =====

@app.get("/api/phoenixguard/available-tasks", response_model=Dict)
async def get_available_tasks(
    capabilities: Optional[str] = None,
    user_id: str = Depends(get_current_user),
    redis_client: redis.Redis = Depends(get_redis)
):
    """Get tasks available for the current user"""
    try:
        # Parse capabilities
        caps = Capabilities()
        if capabilities:
            caps_dict = json.loads(capabilities)
            caps = Capabilities(**caps_dict)
        
        # Get cooperative system
        phoenix_coop = get_cooperative_system(redis_client)
        
        # Filter tasks based on user capabilities and tier
        available_tasks = []
        for task in phoenix_coop.active_tasks.values():
            if task.status != "pending":
                continue
                
            # Check if user can handle the task
            if caps.browser and task.task_type in ["hardware_scrape", "uefi_analysis"]:
                task_package = phoenix_coop.generate_browser_task_package(task)
                if task_package.get('type') != 'unsupported_in_browser':
                    available_tasks.append(task_package)
            elif not caps.browser and task.task_type == "bios_generation":
                # Full system tasks
                if await verify_user_permissions(user_id, "Silver", redis_client):
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
        
        return {
            "available_tasks": available_tasks,
            "user_tier": phoenix_coop.get_contributor_tier(user_id),
            "hardware_configs_liberated": dashboard_data['mission_status']['hardware_configurations_liberated'],
            "total_configs": dashboard_data['mission_status']['hardware_configurations_liberated'],
            "vendors_analyzed": dashboard_data['mission_status']['vendors_analyzed'],
            "active_contributors": dashboard_data['community_stats']['active_contributors_7d'],
            "liberation_progress": dashboard_data['liberation_progress']['percentage_complete']
        }
        
    except Exception as e:
        logger.error(f"Error getting available tasks: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, 
            detail="Failed to load tasks"
        )

@app.post("/api/phoenixguard/claim-task", response_model=Dict)
async def claim_task(
    request: TaskClaimRequest,
    user_id: str = Depends(get_current_user),
    redis_client: redis.Redis = Depends(get_redis)
):
    """Claim a task for execution"""
    try:
        # Get cooperative system
        phoenix_coop = get_cooperative_system(redis_client)
        
        # Register user if not exists
        if user_id not in phoenix_coop.contributors:
            phoenix_coop.register_contributor(user_id, request.capabilities.dict())
        
        # Find best matching task
        best_task = None
        for task in phoenix_coop.active_tasks.values():
            if task.status != "pending":
                continue
                
            # Match task to user capabilities
            if request.capabilities.browser:
                if task.task_type in ["hardware_scrape", "uefi_analysis"]:
                    # Check GPU requirements for analysis tasks
                    if task.task_type == "uefi_analysis" and not request.capabilities.webgl:
                        continue
                    best_task = task
                    break
            else:
                # System tasks for dedicated workers
                if await verify_user_permissions(user_id, "Silver", redis_client):
                    best_task = task
                    break
        
        if not best_task:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No suitable tasks available"
            )
        
        # Claim the task
        best_task.status = "claimed"
        
        # Store task assignment in Redis
        await redis_client.hset(
            f"phoenixguard:claimed_tasks:{user_id}",
            best_task.task_id,
            json.dumps({
                "claimed_at": datetime.now().isoformat(),
                "task_data": best_task.__dict__  # Note: This only works because task.created_at gets serialized
            })
        )
        
        # Generate appropriate task package
        if request.capabilities.browser:
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
        return task_package
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error claiming task: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to claim task"
        )

@app.post("/api/phoenixguard/submit-task/{task_id}", response_model=Dict)
async def submit_task_results(
    task_id: str,
    submission: TaskResultsSubmission,
    user_id: str = Depends(get_current_user),
    redis_client: redis.Redis = Depends(get_redis)
):
    """Submit completed task results"""
    try:
        # Get cooperative system
        phoenix_coop = get_cooperative_system(redis_client)
        
        # Verify task was claimed by this user
        claimed_task_data = await redis_client.hget(f"phoenixguard:claimed_tasks:{user_id}", task_id)
        if not claimed_task_data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Task not found or not claimed by user"
            )
        
        task_info = json.loads(claimed_task_data)
        task = phoenix_coop.active_tasks.get(task_id)
        
        if not task:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Task no longer exists"
            )
        
        # Validate results and calculate quality score
        quality_score = calculate_task_quality(task, submission.results)
        
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
        await redis_client.hset(
            f"phoenixguard:task_results:{task_id}",
            mapping={
                "user_id": user_id,
                "submitted_at": datetime.now().isoformat(),
                "results": json.dumps(submission.results),
                "execution_time": str(submission.execution_time) if submission.execution_time else "",
                "quality_score": str(quality_score),
                "credits_awarded": str(credits_awarded),
                "status": task.status
            }
        )
        
        # Clean up claimed task
        await redis_client.hdel(f"phoenixguard:claimed_tasks:{user_id}", task_id)
        
        # Update user's cloud credits in your platform
        await update_user_cloud_credits(user_id, cloud_credits, redis_client)
        
        logger.info(f"Task {task_id} completed by {user_id} with quality {quality_score:.2f}")
        
        return {
            "status": "success",
            "credits_awarded": credits_awarded,
            "cloud_credits": cloud_credits,
            "quality_score": quality_score,
            "new_tier": phoenix_coop.get_contributor_tier(user_id),
            "message": f"🎉 Great work! Earned {credits_awarded} credits!"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error submitting task results: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to submit results"
        )

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

@app.get("/api/phoenixguard/user/profile", response_model=Dict)
async def get_user_profile(
    user_id: str = Depends(get_current_user),
    redis_client: redis.Redis = Depends(get_redis)
):
    """Get user's PhoenixGuard profile and stats"""
    # Get cooperative system
    phoenix_coop = get_cooperative_system(redis_client)
    
    if user_id not in phoenix_coop.contributors:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not registered"
        )
    
    contributor = phoenix_coop.contributors[user_id]
    
    # Get recent task history
    recent_tasks = []
    task_keys = await redis_client.keys(f"phoenixguard:task_results:*")
    
    for task_key in task_keys:
        result_data = await redis_client.hgetall(task_key)
        if result_data.get('user_id') == user_id:
            recent_tasks.append({
                "task_id": task_key.split(':')[-1],
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
    
    return profile_data

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

@app.get("/api/phoenixguard/dashboard", response_model=Dict)
async def get_global_dashboard(
    redis_client: redis.Redis = Depends(get_redis)
):
    """Get global PhoenixGuard liberation dashboard"""
    # Get cooperative system
    phoenix_coop = get_cooperative_system(redis_client)
    dashboard_data = phoenix_coop.create_cooperative_dashboard_data()
    
    # Add real-time statistics
    dashboard_data["realtime_stats"] = {
        "tasks_completed_today": await get_daily_task_count(redis_client),
        "credits_awarded_today": await get_daily_credits(redis_client),
        "new_contributors_today": get_daily_new_users(phoenix_coop),
        "hardware_configs_today": get_daily_hardware_discoveries(phoenix_coop)
    }
    
    # Add leaderboard
    dashboard_data["leaderboard"] = get_contributor_leaderboard(phoenix_coop)
    
    return dashboard_data

async def get_daily_task_count(redis_client: redis.Redis) -> int:
    """Get tasks completed today"""
    today = datetime.now().strftime('%Y-%m-%d')
    keys = await redis_client.keys(f"phoenixguard:task_results:*")
    
    count = 0
    for key in keys:
        submitted_at = await redis_client.hget(key, 'submitted_at')
        if submitted_at and submitted_at.startswith(today):
            count += 1
    
    return count

async def get_daily_credits(redis_client: redis.Redis) -> int:
    """Get credits awarded today"""
    today = datetime.now().strftime('%Y-%m-%d')
    total = 0
    keys = await redis_client.keys(f"phoenixguard:task_results:*")
    
    for key in keys:
        result = await redis_client.hgetall(key)
        if result.get('submitted_at', '').startswith(today):
            total += int(result.get('credits_awarded', 0))
    
    return total

def get_daily_new_users(phoenix_coop: CooperativePhoenixGuard) -> int:
    """Get new contributors today"""
    today = datetime.now().strftime('%Y-%m-%d')
    return len([c for c in phoenix_coop.contributors.values() 
              if c['registered_at'].startswith(today)])

def get_daily_hardware_discoveries(phoenix_coop: CooperativePhoenixGuard) -> int:
    """Get hardware configs discovered today"""
    # This would query your actual hardware database
    today = datetime.now().strftime('%Y-%m-%d')
    return len([hw for hw in phoenix_coop.hardware_database.values() 
              if hw.get('discovered_date', '').startswith(today)])

def get_contributor_leaderboard(phoenix_coop: CooperativePhoenixGuard, limit: int = 10) -> List[Dict]:
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

async def update_user_cloud_credits(user_id: str, cloud_credits: Dict, redis_client: redis.Redis):
    """Update user's cloud computing credits in your platform"""
    try:
        # This integrates with your existing billing/credits system
        for credit_type, amount in cloud_credits.items():
            await redis_client.hincrbyfloat(f"cloud_credits:{user_id}", credit_type, amount)
        
        logger.info(f"Updated cloud credits for user {user_id}: {cloud_credits}")
        
    except Exception as e:
        logger.error(f"Failed to update cloud credits: {e}")

@app.post("/api/phoenixguard/convert-credits", response_model=Dict)
async def convert_credits(
    request: CloudCreditConversion,
    user_id: str = Depends(get_current_user),
    redis_client: redis.Redis = Depends(get_redis)
):
    """Convert PhoenixGuard credits to cloud computing credits"""
    # Get cooperative system
    phoenix_coop = get_cooperative_system(redis_client)
    
    if user_id not in phoenix_coop.contributors:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not registered"
        )
    
    contributor = phoenix_coop.contributors[user_id]
    
    if contributor['total_credits_earned'] < request.phoenixguard_credits:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Insufficient PhoenixGuard credits"
        )
    
    # Convert credits
    cloud_credits = phoenix_coop.integrate_with_cloud_credits(user_id, request.phoenixguard_credits)
    
    if request.credit_type not in cloud_credits:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid credit type"
        )
    
    # Deduct PhoenixGuard credits and add cloud credits
    contributor['total_credits_earned'] -= request.phoenixguard_credits
    await update_user_cloud_credits(user_id, {request.credit_type: cloud_credits[request.credit_type]}, redis_client)
    
    return {
        "converted": request.phoenixguard_credits,
        "received": {request.credit_type: cloud_credits[request.credit_type]},
        "remaining_phoenixguard_credits": contributor['total_credits_earned']
    }

# ===== BROWSER WIDGET ENDPOINTS =====

@app.get("/api/phoenixguard/widget-data", response_model=Dict)
async def get_widget_data(
    user_id: str = Depends(get_current_user),
    redis_client: redis.Redis = Depends(get_redis)
):
    """Get data for browser contribution widget"""
    # Get cooperative system
    phoenix_coop = get_cooperative_system(redis_client)
    
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
    
    return widget_data

@app.get("/static/phoenixguard-widget.js", response_class=JSONResponse)
async def serve_widget_script():
    """Serve the browser contribution widget script"""
    from cooperative_phoenixguard import create_browser_contribution_widget
    
    widget_js = create_browser_contribution_widget()
    
    response = JSONResponse(
        content=widget_js,
        media_type="application/javascript",
        headers={
            "Cache-Control": "public, max-age=3600",
            "Access-Control-Allow-Origin": "*"
        }
    )
    return response

# ===== WEBHOOK ENDPOINTS FOR INTEGRATION =====

@app.post("/api/phoenixguard/webhook/task-completed", response_model=Dict)
async def task_completed_webhook(
    payload: WebhookPayload,
    redis_client: redis.Redis = Depends(get_redis)
):
    """Webhook for external task completion notifications"""
    # Verify webhook signature (implement your security)
    # In a real implementation, you'd validate payload.signature
    
    # Get cooperative system
    phoenix_coop = get_cooperative_system(redis_client)
    
    task = phoenix_coop.active_tasks.get(payload.task_id)
    if task:
        quality_score = calculate_task_quality(task, payload.results)
        credits = phoenix_coop.award_credits(payload.user_id, task.credits_reward, task.task_type, quality_score)
        cloud_credits = phoenix_coop.integrate_with_cloud_credits(payload.user_id, credits)
        await update_user_cloud_credits(payload.user_id, cloud_credits, redis_client)
    
        # Store results
        await redis_client.hset(
            f"phoenixguard:task_results:{payload.task_id}",
            mapping={
                "user_id": payload.user_id,
                "submitted_at": datetime.now().isoformat(),
                "results": json.dumps(payload.results),
                "quality_score": str(quality_score),
                "credits_awarded": str(credits),
                "status": "completed" if quality_score >= 0.5 else "failed"
            }
        )
    
    return {"status": "processed"}

# ===== HEALTH CHECK =====

@app.get("/api/phoenixguard/health", response_model=Dict)
async def health_check(
    redis_client: redis.Redis = Depends(get_redis)
):
    """Health check endpoint"""
    try:
        # Test Redis connection
        await redis_client.ping()
        
        # Get cooperative system
        phoenix_coop = get_cooperative_system(redis_client)
        
        return {
            "status": "healthy",
            "active_tasks": len(phoenix_coop.active_tasks),
            "registered_contributors": len(phoenix_coop.contributors),
            "redis_connected": True,
            "firmware_liberation_active": True,
            "api_version": "1.0.0"
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return {
            "status": "unhealthy",
            "error": str(e)
        }

# ===== RUN SERVER =====

if __name__ == "__main__":
    import uvicorn
    
    print("🔥 PHOENIXGUARD FASTAPI COOPERATIVE SYSTEM STARTING...")
    print("🌍 Firmware liberation meets cooperative computing!")
    print("📚 OpenAPI docs available at: http://localhost:8001/api/docs")
    print("=" * 50)
    
    # Initialize tasks at startup
    @app.on_event("startup")
    async def startup_event():
        redis_client = redis.Redis(connection_pool=redis_pool)
        phoenix_coop = get_cooperative_system(redis_client)
        
        # Create some demo tasks
        phoenix_coop.create_hardware_scraping_tasks()
        phoenix_coop.create_uefi_analysis_tasks()
        phoenix_coop.create_universal_bios_tasks()
        
        await redis_client.close()
    
    uvicorn.run(app, host="0.0.0.0", port=8001)
