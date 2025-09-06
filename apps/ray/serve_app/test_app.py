from ray import serve


@serve.deployment
class Echo:
    async def __call__(self, request):
        return {"echo": await request.json()}


app = Echo.bind()
