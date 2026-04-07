import sys
import unittest
from unittest.mock import MagicMock, patch

# Mocking external dependencies that are not installed in the environment
mock_fastapi = MagicMock()
mock_pydantic = MagicMock()

# Make decorators return the function they decorate
def mock_decorator(*args, **kwargs):
    def wrapper(func):
        return func
    return wrapper

mock_app = MagicMock()
mock_app.get.side_effect = mock_decorator
mock_app.post.side_effect = mock_decorator
mock_app.delete.side_effect = mock_decorator
mock_app.put.side_effect = mock_decorator

mock_fastapi.FastAPI.return_value = mock_app

# Patch sys.modules before importing the module under test
sys.modules["fastapi"] = mock_fastapi
sys.modules["fastapi.responses"] = MagicMock()
sys.modules["pydantic"] = mock_pydantic

# Mocking the classes used from the imports
class MockBaseModel:
    def __init__(self, **kwargs):
        for k, v in kwargs.items():
            setattr(self, k, v)

mock_pydantic.BaseModel = MockBaseModel

# Now import the module to test
import guest.api_server as api_server

class TestApiServerHealth(unittest.TestCase):

    def test_health_stopped_no_pidfile(self):
        """Verify health() reports 'stopped' when asterisk is not running and pidfile is missing."""
        with patch("subprocess.run") as mock_run, \
             patch("builtins.open") as mock_file_open, \
             patch("guest.api_server._asterisk") as mock_asterisk:

            # 1. Mock subprocess.run to return non-zero exit code for 'pidof asterisk'
            mock_run.return_value = MagicMock(returncode=1)

            # 2. Mock open to raise FileNotFoundError for the pidfile
            mock_file_open.side_effect = FileNotFoundError

            # 3. Call health()
            result = api_server.health()

            # 4. Assertions
            expected_result = {
                "status": "stopped",
                "version": "unknown",
                "wss": "wss://127.0.0.1:8089/asterisk/sip",
                "ws": "ws://127.0.0.1:8088/asterisk/sip",
            }
            self.assertEqual(result, expected_result)

            # Verify pidof was called
            mock_run.assert_any_call(["pidof", "asterisk"], capture_output=True, timeout=5)

            # Verify file open was attempted
            mock_file_open.assert_any_call("/var/run/asterisk/asterisk.pid")

            # Verify _asterisk was NOT called (since running is False)
            mock_asterisk.assert_not_called()

    def test_health_stopped_pidfile_error(self):
        """Verify health() reports 'stopped' when asterisk is not running and pidfile read fails."""
        with patch("subprocess.run") as mock_run, \
             patch("builtins.open") as mock_file_open, \
             patch("guest.api_server._asterisk") as mock_asterisk:

            # 1. Mock subprocess.run to return non-zero exit code for 'pidof asterisk'
            mock_run.return_value = MagicMock(returncode=1)

            # 2. Mock open to raise a generic Exception (swallowed by except Exception: pass)
            mock_file_open.side_effect = Exception("Permission denied")

            # 3. Call health()
            result = api_server.health()

            # 4. Assertions
            self.assertEqual(result["status"], "stopped")
            self.assertEqual(result["version"], "unknown")

    def test_health_running_pidof(self):
        """Verify health() reports 'running' when asterisk is found via pidof."""
        with patch("subprocess.run") as mock_run, \
             patch("guest.api_server._asterisk") as mock_asterisk:

            # 1. Mock subprocess.run to return zero exit code for 'pidof asterisk'
            mock_run.return_value = MagicMock(returncode=0)

            # 2. Mock _asterisk to return a version string
            mock_asterisk.return_value = "Asterisk 20.0.0"

            # 3. Call health()
            result = api_server.health()

            # 4. Assertions
            self.assertEqual(result["status"], "running")
            self.assertEqual(result["version"], "Asterisk 20.0.0")
            mock_asterisk.assert_called_with("core show version", timeout=5)

if __name__ == "__main__":
    unittest.main()
