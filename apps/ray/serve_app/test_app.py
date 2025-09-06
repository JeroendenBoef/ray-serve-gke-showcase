from ray import serve
from starlette.requests import Request


@serve.deployment
class Echo:
    async def __call__(self, request: Request):
        return {"echo": (await request.json())}


app = serve.deployment_graph.bind(Echo.bind())
