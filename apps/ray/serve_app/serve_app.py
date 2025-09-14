import torch
from typing import Any
from ray import serve
import torch.nn.functional as F
from starlette.requests import Request
from transformers import AutoTokenizer, AutoModelForSequenceClassification


@serve.deployment(
    autoscaling_config={"min_replicas": 1, "max_replicas": 5, "target_num_ongoing_requests_per_replica": 4},
    ray_actor_options={"num_cpus": 0.25},
    max_concurrent_queries=32,
)
class Preprocess:
    def __init__(self, model_name: str = "distilbert-base-uncased-finetuned-sst-2-english"):
        self.tokenizer = AutoTokenizer.from_pretrained(model_name)

    def __call__(self, texts: list[str]) -> dict[str, Any]:
        return self.tokenizer(texts, padding=True, truncation=True, max_length=128, return_tensors="pt")


@serve.deployment(
    autoscaling_config={"min_replicas": 1, "max_replicas": 2, "target_num_ongoing_requests_per_replica": 1},
    ray_actor_options={"num_cpus": 0.25, "num_gpus": 1},
    max_concurrent_queries=8,
)
class Inference:
    def __init__(self, model_name: str = "distilbert-base-uncased-finetuned-sst-2-english"):
        device = "cuda" if torch.cuda.is_available() else "cpu"
        self.device = torch.device(device)
        self.model = AutoModelForSequenceClassification.from_pretrained(model_name).to(self.device).eval()

        # model warmup
        with torch.no_grad():
            dummy = {
                "input_ids": torch.zeros(1, 8, dtype=torch.long, device=self.device),
                "attention_mask": torch.ones(1, 8, dtype=torch.long, device=self.device),
            }
            _ = self.model(**dummy)

    @serve.batch(max_batch_size=16, batch_wait_timeout_s=0.01)
    async def __call__(self, batch_inputs: list[dict[str, torch.Tensor]]) -> list[torch.Tensor]:
        sizes = [t["input_ids"].shape[0] for t in batch_inputs]
        input_ids = torch.cat([b["input_ids"] for b in batch_inputs], dim=0).to(self.device)
        attn_mask = torch.cat([b["attention_mask"] for b in batch_inputs], dim=0).to(self.device)

        with torch.no_grad():
            if self.device.type == "cuda":
                with torch.cuda.amp.autocast(dtype=torch.float16):
                    logits_all = self.model(input_ids=input_ids, attention_mask=attn_mask).logits
            else:
                logits_all = self.model(input_ids=input_ids, attention_mask=attn_mask).logits

        logits_all = logits_all.detach().to(dtype=torch.float32, device="cpu")
        return list(torch.split(logits_all, sizes, dim=0))


@serve.deployment(
    autoscaling_config={"min_replicas": 1, "max_replicas": 5, "target_num_ongoing_requests_per_replica": 4},
    ray_actor_options={"num_cpus": 0.25},
    max_concurrent_queries=32,
)
class Postprocess:
    def __call__(self, logits: torch.Tensor) -> list[dict[str, Any]]:
        if logits.dim() == 1:
            logits = logits.unsqueeze(0)
        probs = F.softmax(logits, dim=-1)
        conf, pred = probs.max(dim=-1)
        id2label = {0: "NEGATIVE", 1: "POSITIVE"}
        return [{"label": id2label[p], "confidence": float(c)} for p, c in zip(pred.tolist(), conf.tolist())]


@serve.deployment(route_prefix="/infer", ray_actor_options={"num_cpus": 0.25}, max_concurrent_queries=100)
class Pipeline:
    def __init__(self, pre: Preprocess, infer: Inference, post: Postprocess):
        self.pre = pre
        self.infer = infer
        self.post = post

    async def __call__(self, request: Request):
        payload = await request.json()
        texts = payload.get("inputs") or [payload.get("text", "")]
        if isinstance(texts, str):
            texts = [texts]
        if not texts or not all(isinstance(t, str) and t for t in texts):
            return {"error": "Provide 'inputs': [str,...] or 'text': str"}, 400

        tokens = await self.pre.remote(texts)
        logits = await self.infer.remote(tokens)
        return await self.post.remote(logits)


graph = Pipeline.bind(Preprocess.bind(), Inference.bind(), Postprocess.bind())
