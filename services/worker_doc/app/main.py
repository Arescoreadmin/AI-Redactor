import os, json, asyncio, uuid, time
from loguru import logger
from nats.aio.client import Client as NATS

NATS_URL = os.getenv("NATS_URL","nats://nats:4222")

async def run():
    nc = NATS()
    await nc.connect(servers=[NATS_URL])
    logger.info("worker_doc online")

    async def on_start(msg):
        evt = json.loads(msg.data.decode())
        job_id = evt["job_id"]
        logger.info("processing %s", job_id)
        # simulate work
        await asyncio.sleep(0.2)
        # propose a fake detection
        detection = {
            "job_id": job_id,
            "detector": "rule",
            "confidence": 0.99
        }
        await nc.publish("detections.proposed", json.dumps(detection).encode())

    await nc.subscribe("jobs.doc.start", cb=on_start)

    while True:
        await asyncio.sleep(1)

if __name__ == "__main__":
    asyncio.run(run())
