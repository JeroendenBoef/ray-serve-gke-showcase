import torch
from typing import Any
from ray import serve
from starlette.requests import Request
from transformers import AutoTokenizer, AutoModelForSequenceClassification


@serve.deployment(
    autoscaling_config={"min_replicas": 1, "max_replicas": 5, "target_ongoing_requests": 8},
    ray_actor_options={"num_cpus": 0.25},
    max_concurrent_queries=32,
)
class Preprocess:
    def __init__(self, model_name: str = "distilbert-base-uncased-finetuned-sst-2-english"):
        self.tokenizer = AutoTokenizer.from_pretrained(model_name)

    def __call__(self, texts: list[str]) -> dict[str, Any]:
        return self.tokenizer(texts, padding=True, truncation=True, max_length=128, return_tensors="pt")


@serve.deployment(
    autoscaling_config={"min_replicas": 1, "max_replicas": 2, "target_ongoing_requests": 2},
    ray_actor_options={"num_cpus": 0.25, "num_gpus": 1},
    max_concurrent_queries=8,
)
class Inference:
    def __init__(self, model_name: str = "distilbert-base-uncased-finetuned-sst-2-english"):
        device = "cuda" if torch.cuda.is_available() else "cpu"
        self.device = torch.device(device)
        self.model = AutoModelForSequenceClassification.from_pretrained(model_name).to(self.device).eval()

    @serve.batch(max_batch_size=16, batch_wait_timeout_s=0.01)
    def __call__(self, batch_inputs: list[dict[str, torch.Tensor]]) -> list[torch.Tensor]:
        input_ids = torch.cat([b["input_ids"] for b in batch_inputs], dim=0).to(self.device)
        attn_mask = torch.cat([b["attention_mask"] for b in batch_inputs], dim=0).to(self.device)
        with torch.no_grad():
            logits = self.model(input_ids=input_ids, attention_mask=attn_mask).logits
        return [logits.cpu()]


@serve.deployment(
    autoscaling_config={"min_replicas": 1, "max_replicas": 5, "target_ongoing_requests": 8},
    ray_actor_options={"num_cpus": 0.25},
    max_concurrent_queries=32,
)
class Postprocess:
    def __call__(self, logits_list: list[torch.Tensor]) -> list[dict[str, Any]]:
        import torch.nn.functional as F

        logits = logits_list[0]
        probs = F.softmax(logits, dim=-1)
        conf, pred = torch.max(probs, dim=-1)
        id2label = {0: "NEGATIVE", 1: "POSITIVE"}
        return [{"label": id2label[int(p)], "confidence": float(c)} for p, c in zip(pred, conf)]


@serve.deployment(route_prefix="/infer", ray_actor_options={"num_cpus": 0.25})
class Pipeline:
    def __init__(self, pre: Preprocess, infer: Inference, post: Postprocess):
        self.pre = pre
        self.infer = infer
        self.post = post

    async def __call__(self, request: Request):
        payload = await request.json()
        texts = payload.get("inputs") or [payload["text"]]
        tokens = await self.pre.remote(texts)
        logits = await self.infer.remote(tokens)
        out = await self.post.remote(logits)
        return out


graph = Pipeline.bind(Preprocess.bind(), Inference.bind(), Postprocess.bind())
