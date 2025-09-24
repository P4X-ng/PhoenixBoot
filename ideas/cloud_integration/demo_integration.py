#!/usr/bin/env python3
"""
PhoenixGuard Cooperative Cloud Integration Demo
==============================================

This script demonstrates how to integrate the PhoenixGuard hardware liberation
system with your cooperative cloud computing platform.

Features demonstrated:
- FastAPI endpoints for task distribution
- Browser-based contribution system 
- Credit system integration
- Real-time dashboard
- WebGL GPU acceleration
- Tailscale VPN multi-tenancy
- Automatic scaling and resource management
"""

import asyncio
import json
import time
import requests
from pathlib import Path

# Demo configuration
API_BASE_URL = "http://localhost:8001/api/phoenixguard"
DEMO_USER_ID = "demo_user_123"

async def main():
    """Run the integration demo"""
    print("🔥 PHOENIXGUARD COOPERATIVE CLOUD INTEGRATION DEMO")
    print("=" * 60)
    
    print("🚀 Starting demonstration of cooperative cloud integration...")
    print("🌍 This shows how PhoenixGuard integrates with your platform!")
    print()
    
    # Wait for API to be ready
    print("⏳ Waiting for FastAPI server to start...")
    await wait_for_api()
    
    # Step 1: Check health
    print("🏥 Step 1: Health Check")
    health = await check_health()
    print(f"   ✅ API Status: {health.get('status', 'Unknown')}")
    print(f"   📊 Active Tasks: {health.get('active_tasks', 0)}")
    print(f"   👥 Contributors: {health.get('registered_contributors', 0)}")
    print()
    
    # Step 2: Get available tasks
    print("📋 Step 2: Available Tasks")
    tasks = await get_available_tasks()
    print(f"   🎯 Available tasks: {len(tasks.get('available_tasks', []))}")
    print(f"   🏆 User tier: {tasks.get('user_tier', 'Unknown')}")
    print(f"   📈 Liberation progress: {tasks.get('liberation_progress', 0):.1f}%")
    print()
    
    # Step 3: Simulate browser contribution
    print("🌐 Step 3: Browser-Based Contribution")
    await simulate_browser_contribution()
    print()
    
    # Step 4: Show dashboard
    print("📊 Step 4: Global Dashboard")
    dashboard = await get_dashboard()
    await display_dashboard(dashboard)
    print()
    
    # Step 5: Credit conversion demo
    print("💰 Step 5: Credit Conversion Demo")
    await demo_credit_conversion()
    print()
    
    # Step 6: Widget integration
    print("🔧 Step 6: Browser Widget Integration")
    await demo_widget_integration()
    print()
    
    print("🎉 DEMO COMPLETE!")
    print("=" * 60)
    print("🚀 Ready to integrate with your cooperative cloud platform!")
    print("📚 Check API docs at: http://localhost:8001/api/docs")

async def wait_for_api():
    """Wait for API to be ready"""
    for i in range(30):  # Wait up to 30 seconds
        try:
            response = requests.get(f"{API_BASE_URL}/health", timeout=2)
            if response.status_code == 200:
                return
        except:
            pass
        await asyncio.sleep(1)
        print(f"   ⏳ Waiting for API... ({i+1}/30)")
    
    print("⚠️  API not responding. Starting FastAPI server first:")
    print("   python fastapi_endpoints.py")
    return

async def check_health():
    """Check API health"""
    try:
        response = requests.get(f"{API_BASE_URL}/health")
        return response.json()
    except Exception as e:
        return {"status": "error", "message": str(e)}

async def get_available_tasks():
    """Get available tasks"""
    try:
        # Simulate browser capabilities
        caps = {
            "browser": True,
            "webgl": True,
            "webworkers": True,
            "cpu_cores": 4,
            "ram_gb": 8,
            "gpu_count": 1
        }
        
        response = requests.get(
            f"{API_BASE_URL}/available-tasks",
            params={"capabilities": json.dumps(caps)},
            headers={"X-User-ID": DEMO_USER_ID}
        )
        return response.json()
    except Exception as e:
        return {"error": str(e)}

async def simulate_browser_contribution():
    """Simulate a user contributing via browser"""
    print("   🖥️  Simulating browser-based hardware scraping...")
    
    # Claim a task
    try:
        caps = {
            "browser": True,
            "webgl": True,
            "webworkers": True,
            "cpu_cores": 4,
            "ram_gb": 8,
            "gpu_count": 1
        }
        
        response = requests.post(
            f"{API_BASE_URL}/claim-task",
            json={"capabilities": caps},
            headers={"X-User-ID": DEMO_USER_ID}
        )
        
        if response.status_code == 200:
            task = response.json()
            print(f"   ✅ Claimed task: {task.get('task_id', 'Unknown')}")
            print(f"   📝 Description: {task.get('description', 'N/A')}")
            print(f"   💰 Credits reward: {task.get('credits', 0)}")
            
            # Simulate task completion
            await asyncio.sleep(2)  # Simulate work
            
            # Submit results
            results = {
                "hardware_configs": [
                    {"vendor": "ASUS", "model": "ROG Strix", "bios_version": "1.23"},
                    {"vendor": "MSI", "model": "Gaming X", "bios_version": "2.45"}
                ],
                "uefi_variables": 25,
                "execution_time_ms": 2000
            }
            
            submit_response = requests.post(
                f"{API_BASE_URL}/submit-task/{task.get('task_id')}",
                json={"results": results},
                headers={"X-User-ID": DEMO_USER_ID}
            )
            
            if submit_response.status_code == 200:
                result = submit_response.json()
                print(f"   🎉 Task completed! Earned {result.get('credits_awarded', 0)} credits")
                print(f"   🏆 New tier: {result.get('new_tier', 'Unknown')}")
            else:
                print(f"   ⚠️  Failed to submit results: {submit_response.status_code}")
        
        else:
            print(f"   ⚠️  Failed to claim task: {response.status_code}")
            if response.status_code == 404:
                print("   📝 No tasks available (this is normal for demo)")
    
    except Exception as e:
        print(f"   ❌ Error: {e}")

async def get_dashboard():
    """Get global dashboard data"""
    try:
        response = requests.get(f"{API_BASE_URL}/dashboard")
        return response.json()
    except Exception as e:
        return {"error": str(e)}

async def display_dashboard(dashboard):
    """Display dashboard information"""
    if "error" in dashboard:
        print(f"   ❌ Dashboard error: {dashboard['error']}")
        return
    
    mission = dashboard.get('mission_status', {})
    community = dashboard.get('community_stats', {})
    realtime = dashboard.get('realtime_stats', {})
    
    print("   🎯 Mission Status:")
    print(f"      📄 Hardware configs liberated: {mission.get('hardware_configurations_liberated', 0)}")
    print(f"      🏭 Vendors analyzed: {mission.get('vendors_analyzed', 0)}")
    print(f"      🔍 UEFI variables discovered: {mission.get('uefi_variables_discovered', 0)}")
    
    print("   👥 Community Stats:")
    print(f"      🙋 Total contributors: {community.get('total_contributors', 0)}")
    print(f"      ⚡ Active (7 days): {community.get('active_contributors_7d', 0)}")
    print(f"      💰 Credits awarded: {community.get('total_credits_awarded', 0)}")
    
    print("   📊 Today's Activity:")
    print(f"      ✅ Tasks completed: {realtime.get('tasks_completed_today', 0)}")
    print(f"      💎 Credits awarded: {realtime.get('credits_awarded_today', 0)}")
    print(f"      🆕 New contributors: {realtime.get('new_contributors_today', 0)}")

async def demo_credit_conversion():
    """Demo credit conversion to cloud computing resources"""
    print("   🔄 Converting PhoenixGuard credits to cloud computing credits...")
    
    # First get user profile to see available credits
    try:
        profile_response = requests.get(
            f"{API_BASE_URL}/user/profile",
            headers={"X-User-ID": DEMO_USER_ID}
        )
        
        if profile_response.status_code == 200:
            profile = profile_response.json()
            credits = profile.get('total_credits', 0)
            print(f"   💰 Available PhoenixGuard credits: {credits}")
            
            if credits >= 10:
                # Convert some credits
                conversion_response = requests.post(
                    f"{API_BASE_URL}/convert-credits",
                    json={
                        "phoenixguard_credits": 10,
                        "credit_type": "container_hours"
                    },
                    headers={"X-User-ID": DEMO_USER_ID}
                )
                
                if conversion_response.status_code == 200:
                    result = conversion_response.json()
                    print(f"   ✅ Converted {result.get('converted', 0)} PG credits")
                    print(f"   🐳 Received: {result.get('received', {})}")
                    print(f"   💎 Remaining: {result.get('remaining_phoenixguard_credits', 0)} PG credits")
                else:
                    print(f"   ⚠️  Conversion failed: {conversion_response.status_code}")
            else:
                print("   📝 Not enough credits for conversion demo")
        
        else:
            print(f"   ⚠️  Failed to get profile: {profile_response.status_code}")
    
    except Exception as e:
        print(f"   ❌ Error: {e}")

async def demo_widget_integration():
    """Demo browser widget integration"""
    print("   🔧 Browser widget integration example:")
    print()
    
    # Get widget data
    try:
        response = requests.get(
            f"{API_BASE_URL}/widget-data",
            headers={"X-User-ID": DEMO_USER_ID}
        )
        
        if response.status_code == 200:
            widget_data = response.json()
            
            print("   📱 Widget HTML Integration:")
            print("   ```html")
            print('   <div id="phoenixguard-widget"></div>')
            print('   <script src="http://localhost:8001/static/phoenixguard-widget.js"></script>')
            print("   ```")
            print()
            
            print("   📊 Widget Data:")
            user_stats = widget_data.get('user_stats', {})
            global_impact = widget_data.get('global_impact', {})
            
            print(f"      👤 User credits: {user_stats.get('credits_earned', 0)}")
            print(f"      🏆 User tier: {user_stats.get('tier', 'N/A')}")
            print(f"      📄 Global configs: {global_impact.get('configs_liberated', 0)}")
            print(f"      🌍 Active contributors: {global_impact.get('active_contributors', 0)}")
            print(f"      💻 Browser tasks available: {widget_data.get('available_browser_tasks', 0)}")
        
        else:
            print(f"   ⚠️  Widget data failed: {response.status_code}")
    
    except Exception as e:
        print(f"   ❌ Widget error: {e}")
    
    print()
    print("   🚀 Integration Benefits:")
    print("      ✅ Zero-friction contribution via browser")
    print("      🔒 Privacy-first (processing happens locally)")
    print("      💰 Automatic credit rewards")
    print("      ⚡ GPU acceleration via WebGL")
    print("      🌐 No downloads or installations required")
    print("      🔗 Easy integration with your existing platform")

if __name__ == "__main__":
    asyncio.run(main())
