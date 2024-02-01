from fastapi.testclient import TestClient
from src.main import app

client = TestClient(app)


def test_health():

    response = client.get("/hello-world")
    data = response.json()

    assert response.status_code == 200
    assert "message" in data
    assert "timestamp" in data
    assert data["message"] == "hello world"
