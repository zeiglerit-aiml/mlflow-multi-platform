from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="AIOFFICE_", env_file=".env")

    environment: str = "local"
    mlflow_tracking_uri: str = "http://localhost:5000"
    model_catalog_path: Path = Path("config/model_catalog.yaml")
    algorithm_catalog_path: Path = Path("config/algorithm_catalog.yaml")
    model_service_base_url: str = "http://localhost:8010"
    max_parallel_models: int = 5
    require_promotion_approval: bool = True


@lru_cache
def get_settings() -> Settings:
    return Settings()

