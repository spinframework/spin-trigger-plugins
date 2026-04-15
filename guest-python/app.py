import spin_cron
from spin_cron.imports.spin_cron_cron_types_3_0_0 import Metadata
from spin_sdk import variables

class SpinCron(spin_cron.SpinCron):
    async def handle_cron_event(self, metadata: Metadata) -> None:
        temp = await variables.get("something")
        print("[" + str(metadata.timestamp) +"] " + "Hello every " + temp)
