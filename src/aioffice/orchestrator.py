from .comparison import compare_results
from .planner import ProblemPlanner
from .router import ModelRouter
from .schemas import AnalysisResponse, ExecutionMode, InferenceRequest


class MLOrchestrator:
    def __init__(self, planner: ProblemPlanner, router: ModelRouter) -> None:
        self.planner = planner
        self.router = router

    async def analyze(self, request: InferenceRequest) -> AnalysisResponse:
        plan = self.planner.create_plan(request)
        response = AnalysisResponse(status="planned", plan=plan)
        if plan.mode == ExecutionMode.RECOMMEND or not plan.candidates:
            return response

        results = await self.router.execute(plan.candidates, request.data)
        response.comparison = compare_results(plan.task, results)
        response.status = "completed"
        return response

