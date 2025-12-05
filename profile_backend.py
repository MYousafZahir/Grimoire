#!/usr/bin/env python3
"""
Backend Profiling Script for Grimoire
Uses Python's built-in profiling tools instead of custom profiler.
"""

import cProfile
import pstats
import time
import json
import os
import sys
from pathlib import Path
from typing import Dict, Any, List
import subprocess
import threading
from datetime import datetime

# Add backend directory to path
backend_dir = Path(__file__).parent / "backend"
sys.path.insert(0, str(backend_dir))

class BackendProfiler:
    """Profiles Grimoire backend using Python's built-in tools."""

    def __init__(self):
        self.profile_dir = Path.home() / "Documents" / "GrimoireProfiles"
        self.profile_dir.mkdir(exist_ok=True)

    def profile_endpoint(self, endpoint: str, method: str = "POST",
                        data: Dict[str, Any] = None,
                        iterations: int = 10) -> Dict[str, Any]:
        """
        Profile a single API endpoint.

        Args:
            endpoint: API endpoint path (e.g., "/create-folder")
            method: HTTP method
            data: Request data
            iterations: Number of iterations to run

        Returns:
            Dictionary with profiling results
        """
        import requests

        url = f"http://127.0.0.1:8000{endpoint}"
        headers = {"Content-Type": "application/json"}

        # Prepare request data
        request_data = data or {}

        results = {
            "endpoint": endpoint,
            "method": method,
            "iterations": iterations,
            "timings": [],
            "success_count": 0,
            "error_count": 0,
            "errors": []
        }

        print(f"Profiling {method} {endpoint} ({iterations} iterations)...")

        for i in range(iterations):
            try:
                start_time = time.time()

                if method.upper() == "POST":
                    response = requests.post(url, json=request_data, headers=headers)
                elif method.upper() == "GET":
                    response = requests.get(url, headers=headers)
                else:
                    raise ValueError(f"Unsupported method: {method}")

                elapsed = time.time() - start_time
                results["timings"].append(elapsed * 1000)  # Convert to ms

                if response.status_code == 200:
                    results["success_count"] += 1
                else:
                    results["error_count"] += 1
                    results["errors"].append({
                        "iteration": i,
                        "status_code": response.status_code,
                        "response": response.text[:200]
                    })

            except Exception as e:
                elapsed = time.time() - start_time
                results["timings"].append(elapsed * 1000)
                results["error_count"] += 1
                results["errors"].append({
                    "iteration": i,
                    "error": str(e)
                })

        # Calculate statistics
        if results["timings"]:
            results["avg_time_ms"] = sum(results["timings"]) / len(results["timings"])
            results["min_time_ms"] = min(results["timings"])
            results["max_time_ms"] = max(results["timings"])
            results["p95_time_ms"] = sorted(results["timings"])[int(len(results["timings"]) * 0.95)]
        else:
            results["avg_time_ms"] = 0
            results["min_time_ms"] = 0
            results["max_time_ms"] = 0
            results["p95_time_ms"] = 0

        return results

    def profile_with_cprofile(self, endpoint: str, data: Dict[str, Any] = None):
        """
        Profile endpoint using cProfile for detailed function-level analysis.
        """
        import requests

        url = f"http://127.0.0.1:8000{endpoint}"
        headers = {"Content-Type": "application/json"}
        request_data = data or {}

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        profile_file = self.profile_dir / f"cprofile_{endpoint.replace('/', '_')}_{timestamp}.prof"

        print(f"Running cProfile on {endpoint}...")

        def make_request():
            response = requests.post(url, json=request_data, headers=headers)
            return response.status_code

        # Run cProfile
        cProfile.runctx('make_request()', globals(), locals(), str(profile_file))

        # Analyze and print results
        print(f"\n{cProfile Analysis for {endpoint}:")
        print("=" * 60)

        stats = pstats.Stats(str(profile_file))
        stats.strip_dirs()
        stats.sort_stats('cumulative')
        stats.print_stats(20)  # Top 20 functions

        return str(profile_file)

    def profile_folder_creation_flow(self):
        """Profile the complete folder creation flow."""
        print("\n" + "=" * 60)
        print("Profiling Folder Creation Flow")
        print("=" * 60)

        # Test data
        test_folder = f"test_folder_{int(time.time())}"

        # Profile create-folder endpoint
        create_results = self.profile_endpoint(
            "/create-folder",
            method="POST",
            data={"folder_path": test_folder},
            iterations=5
        )

        self._print_results(create_results)

        # Also profile notes endpoint to see tree updates
        notes_results = self.profile_endpoint("/notes", method="GET", iterations=3)
        self._print_results(notes_results)

        return {
            "create_folder": create_results,
            "get_notes": notes_results
        }

    def profile_note_deletion_flow(self):
        """Profile the complete note deletion flow."""
        print("\n" + "=" * 60)
        print("Profiling Note Deletion Flow")
        print("=" * 60)

        # First create a test note to delete
        test_note = f"test_note_{int(time.time())}"

        create_results = self.profile_endpoint(
            "/create-folder",  # Using folder as test note
            method="POST",
            data={"folder_path": test_note},
            iterations=1
        )

        if create_results["success_count"] > 0:
            # Profile deletion
            delete_results = self.profile_endpoint(
                "/delete-note",
                method="POST",
                data={"note_id": test_note},
                iterations=5
            )

            self._print_results(delete_results)
            return delete_results
        else:
            print("Failed to create test note for deletion profiling")
            return None

    def profile_backend_startup(self):
        """Profile backend startup time."""
        print("\n" + "=" * 60)
        print("Profiling Backend Startup")
        print("=" * 60)

        # Kill any existing backend process
        subprocess.run(["pkill", "-f", "uvicorn main:app"],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1)

        # Start backend with profiling
        startup_times = []

        for i in range(3):  # Test 3 startups
            print(f"Startup attempt {i + 1}/3...")

            # Start backend in background
            backend_process = subprocess.Popen(
                ["python", "-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", "8000"],
                cwd=str(backend_dir),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )

            # Wait for backend to be ready
            start_time = time.time()
            ready = False

            for _ in range(30):  # Wait up to 30 seconds
                time.sleep(1)
                try:
                    import requests
                    response = requests.get("http://127.0.0.1:8000/", timeout=1)
                    if response.status_code == 200:
                        ready = True
                        break
                except:
                    continue

            if ready:
                elapsed = time.time() - start_time
                startup_times.append(elapsed)
                print(f"  Started in {elapsed:.2f} seconds")
            else:
                print("  Failed to start within 30 seconds")

            # Kill backend
            backend_process.terminate()
            backend_process.wait()
            time.sleep(2)

        if startup_times:
            avg_startup = sum(startup_times) / len(startup_times)
            print(f"\nAverage startup time: {avg_startup:.2f} seconds")
            print(f"Startup times: {[f'{t:.2f}s' for t in startup_times]}")

            return {
                "startup_times": startup_times,
                "average_startup_seconds": avg_startup
            }

        return None

    def run_comprehensive_profile(self):
        """Run comprehensive profiling of all critical endpoints."""
        print("=" * 60)
        print("Comprehensive Backend Profiling")
        print("=" * 60)

        results = {}

        # 1. Profile startup
        startup_results = self.profile_backend_startup()
        if startup_results:
            results["startup"] = startup_results

        # Start backend for other tests
        print("\nStarting backend for endpoint profiling...")
        backend_process = subprocess.Popen(
            ["python", "-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", "8000"],
            cwd=str(backend_dir),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )

        # Wait for backend to start
        time.sleep(3)

        try:
            # 2. Profile health check
            print("\nProfiling health check endpoint...")
            health_results = self.profile_endpoint("/", method="GET", iterations=10)
            results["health_check"] = health_results
            self._print_results(health_results)

            # 3. Profile folder creation
            folder_results = self.profile_folder_creation_flow()
            results["folder_creation"] = folder_results

            # 4. Profile note deletion
            delete_results = self.profile_note_deletion_flow()
            if delete_results:
                results["note_deletion"] = delete_results

            # 5. Profile with cProfile for detailed analysis
            print("\n" + "=" * 60)
            print("Running Detailed cProfile Analysis")
            print("=" * 60)

            cprofile_file = self.profile_with_cprofile(
                "/create-folder",
                data={"folder_path": f"cprofile_test_{int(time.time())}"}
            )
            results["cprofile_file"] = cprofile_file

        finally:
            # Clean up
            print("\nStopping backend...")
            backend_process.terminate()
            backend_process.wait()

        # Save results
        self._save_results(results)

        return results

    def _print_results(self, results: Dict[str, Any]):
        """Print profiling results in a readable format."""
        if "endpoint" in results:
            print(f"\n{results['method']} {results['endpoint']}:")
            print(f"  Success: {results['success_count']}/{results['iterations']}")

            if results['timings']:
                print(f"  Avg time: {results['avg_time_ms']:.2f}ms")
                print(f"  Min time: {results['min_time_ms']:.2f}ms")
                print(f"  Max time: {results['max_time_ms']:.2f}ms")
                print(f"  P95 time: {results['p95_time_ms']:.2f}ms")

            if results['errors']:
                print(f"  Errors: {len(results['errors'])}")
                for error in results['errors'][:3]:  # Show first 3 errors
                    print(f"    - {error}")

    def _save_results(self, results: Dict[str, Any]):
        """Save profiling results to JSON file."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        results_file = self.profile_dir / f"profile_results_{timestamp}.json"

        # Convert any non-serializable objects
        def serialize(obj):
            if isinstance(obj, Path):
                return str(obj)
            raise TypeError(f"Object of type {type(obj)} is not JSON serializable")

        with open(results_file, 'w') as f:
            json.dump(results, f, indent=2, default=serialize)

        print(f"\nResults saved to: {results_file}")

    def monitor_backend_performance(self, duration_seconds: int = 60):
        """
        Monitor backend performance over time.

        Args:
            duration_seconds: How long to monitor
        """
        print(f"\nMonitoring backend performance for {duration_seconds} seconds...")
        print("Press Ctrl+C to stop early")

        # Start backend
        backend_process = subprocess.Popen(
            ["python", "-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", "8000"],
            cwd=str(backend_dir),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )

        time.sleep(3)  # Wait for backend to start

        monitor_data = {
            "start_time": datetime.now().isoformat(),
            "duration_seconds": duration_seconds,
            "health_checks": [],
            "folder_creations": []
        }

        try:
            import requests
            start_time = time.time()

            while time.time() - start_time < duration_seconds:
                # Perform health check
                health_start = time.time()
                try:
                    response = requests.get("http://127.0.0.1:8000/", timeout=5)
                    health_time = (time.time() - health_start) * 1000

                    monitor_data["health_checks"].append({
                        "timestamp": datetime.now().isoformat(),
                        "response_time_ms": health_time,
                        "status_code": response.status_code
                    })

                    # Every 10 seconds, create a folder
                    if len(monitor_data["folder_creations"]) < 5:  # Limit to 5 folders
                        folder_start = time.time()
                        folder_name = f"monitor_{int(time.time())}"

                        response = requests.post(
                            "http://127.0.0.1:8000/create-folder",
                            json={"folder_path": folder_name},
                            timeout=10
                        )

                        folder_time = (time.time() - folder_start) * 1000

                        monitor_data["folder_creations"].append({
                            "timestamp": datetime.now().isoformat(),
                            "folder_name": folder_name,
                            "response_time_ms": folder_time,
                            "status_code": response.status_code
                        })

                except Exception as e:
                    monitor_data["health_checks"].append({
                        "timestamp": datetime.now().isoformat(),
                        "error": str(e)
                    })

                time.sleep(5)  # Check every 5 seconds

        except KeyboardInterrupt:
            print("\nMonitoring stopped by user")

        finally:
            # Clean up
            backend_process.terminate()
            backend_process.wait()

            # Delete test folders
            try:
                import requests
                for folder_data in monitor_data["folder_creations"]:
                    if "folder_name" in folder_data:
                        requests.post(
                            "http://127.0.0.1:8000/delete-note",
                            json={"note_id": folder_data["folder_name"]},
                            timeout=5
                        )
            except:
                pass

        # Save monitor data
        self._save_results(monitor_data)

        # Print summary
        print("\nMonitoring Summary:")
        print(f"  Health checks: {len(monitor_data['health_checks'])}")
        print(f"  Folder creations: {len(monitor_data['folder_creations'])}")

        if monitor_data["health_checks"]:
            response_times = [h["response_time_ms"] for h in monitor_data["health_checks"]
                            if "response_time_ms" in h]
            if response_times:
                avg_time = sum(response_times) / len(response_times)
                print(f"  Avg health check response: {avg_time:.2f}ms")

        return monitor_data


def main():
    """Main function to run profiling."""
    profiler = BackendProfiler()

    print("Grimoire Backend Profiler")
    print("=" * 60)
    print("Options:")
    print("  1. Comprehensive profile (all endpoints)")
    print("  2. Profile folder creation flow")
    print("  3. Profile note deletion flow")
    print("  4. Profile backend startup")
    print("  5. Monitor backend performance")
    print("  6. Run cProfile on specific endpoint")
    print("  7. Exit")

    try:
        choice = input("\nSelect option (1-7): ").strip()

        if choice == "1":
            profiler.run_comprehensive_profile()
        elif choice == "2":
            profiler.profile_folder_creation_flow()
        elif choice == "3":
            profiler.profile_note_deletion_flow()
        elif choice == "4":
            profiler.profile_backend_startup()
        elif choice == "5":
            duration = input("Monitor duration in seconds (default 60): ").strip()
            duration = int(duration) if duration.isdigit() else 60
            profiler.monitor_backend_performance(duration)
        elif choice == "6":
            endpoint = input("Endpoint to profile (e.g., /create-folder): ").strip()
            data_str = input("JSON data (optional, e.g., {\"folder_path\":\"test\"}): ").strip()
            data = json.loads(data_str) if data_str else None
            profiler.profile_with_cprofile(endpoint, data)
        elif choice == "7":
            print("Exiting...")
        else:
            print("Invalid choice")

    except KeyboardInterrupt:
        print("\n\nProfiling cancelled")
    except Exception as e:
        print(f"\nError during profiling: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
