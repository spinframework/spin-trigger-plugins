from bindings import wit_world
from bindings import cron_types
from spin_sdk import variables

class SpinCron(wit_world.WitWorld):
    async def handle_cron_event(self, metadata: cron_types.Metadata) -> None:
        temp = await variables.get("something")
        print("[" + str(metadata.timestamp) +"] " + "Hello every " + temp)