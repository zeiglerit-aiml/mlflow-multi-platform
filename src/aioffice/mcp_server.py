"""MCP control interface. It reuses the same orchestration core as FastAPI."""

from typing import Any

from mcp.server.fastmcp import FastMCP

from .dependencies import get_catalog, get_orchestrator
from .schemas import InferenceRequest

mcp = FastMCP("AI Office ML Intelligence")


@mcp.resource("ml://algorithms/catalog")
def algorithm_catalog() -> str:
    """Return algorithms, supported tasks, frameworks, and constraints."""
    return str(get_catalog().algorithms)


@mcp.resource("ml://models/production")
def production_models() -> str:
    """Return registered models currently eligible for routing."""
    ready = [item for item in get_catalog().models if item.get("status") == "ready"]
    return str(ready)


@mcp.tool()
async def recommend_algorithms(
    question: str,
    task: str | None = None,
    maximum_models: int = 3,
) -> dict[str, Any]:
    """Formulate an ML problem and recommend compatible registered models."""
    request = InferenceRequest(
        question=question,
        task=task,
        mode="recommend",
        maximum_models=maximum_models,
    )
    result = await get_orchestrator().analyze(request)
    return result.model_dump(mode="json")


@mcp.tool()
async def compare_compatible_models(
    question: str,
    data: list[dict[str, Any]] | dict[str, Any],
    task: str | None = None,
    preferred_algorithms: list[str] | None = None,
    maximum_models: int = 3,
) -> dict[str, Any]:
    """Execute compatible models and return deterministic normalized comparisons."""
    request = InferenceRequest(
        question=question,
        task=task,
        data=data,
        preferred_algorithms=preferred_algorithms or [],
        mode="compare",
        maximum_models=maximum_models,
    )
    result = await get_orchestrator().analyze(request)
    return result.model_dump(mode="json")


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()

