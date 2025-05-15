import os
from typing import List
from pydantic import AnyHttpUrl, BaseSettings

class Settings(BaseSettings):
    API_V1_STR: str = "/api/v1"
    JWT_SECRET_KEY: str = os.getenv("JWT_SECRET_KEY", "change_this_in_production")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days
    
    # CORS
    CORS_ORIGINS: List[AnyHttpUrl] = [
        "http://localhost:3000",  # Frontend development
        "https://tasking-monitor.example.com",  # Production
    ]
    
    # CSV Settings
    CSV_DIR: str = os.getenv("CSV_DIR", "/data/exports")
    TASKS_CSV: str = os.getenv("TASKS_CSV", "tasks_daily.csv")
    CONTENT_CSV: str = os.getenv("CONTENT_CSV", "task_content_daily.csv")
    
    # LLM Settings
    LLM_PROVIDER: str = os.getenv("LLM_PROVIDER", "ollama")  # 'ollama' or 'openai'
    LLM_ENABLED: bool = os.getenv("LLM_ENABLED", "True").lower() in ("true", "1", "t")
    
    # Ollama Settings
    OLLAMA_BASE_URL: str = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434")
    OLLAMA_MODEL: str = os.getenv("OLLAMA_MODEL", "llama3")
    
    # OpenAI Settings (fallback)
    OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
    OPENAI_MODEL: str = os.getenv("OPENAI_MODEL", "gpt-3.5-turbo")
    
    class Config:
        case_sensitive = True
        env_file = ".env"

settings = Settings()
