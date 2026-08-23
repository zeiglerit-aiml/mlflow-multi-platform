from functools import lru_cache

from .catalog import Catalog
from .orchestrator import MLOrchestrator
from .planner import ProblemPlanner
from .router import ModelRouter
from .settings import get_settings


@lru_cache
def get_catalog() -> Catalog:
    settings = get_settings()
    return Catalog(settings.algorithm_catalog_path, settings.model_catalog_path)


@lru_cache
def get_orchestrator() -> MLOrchestrator:
    settings = get_settings()
    catalog = get_catalog()
    return MLOrchestrator(
        planner=ProblemPlanner(catalog),
        router=ModelRouter(base_url=settings.model_service_base_url),
    )
