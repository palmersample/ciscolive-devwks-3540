import logging
import os
from dotenv import dotenv_values
from genie.harness.main import gRun
from netbox_testbed import netbox, build_testbed

logger = logging.getLogger()

script_basepath = os.path.dirname(__file__)
project_root = os.path.join(script_basepath, "..")
config = dotenv_values(f"{project_root}/workshop-env")

NETBOX_INVENTORY_FILTER = {
    "location": "devnet-zone",
    "cf_workshop_pod_number": config["POD_NUMBER"]
}


def main(runtime):
    runtime.job.name = "Compliance test using Sources of Truth"

    testbed = build_testbed(device_filter=NETBOX_INVENTORY_FILTER)

    gRun(subsection_datafile=f"{script_basepath}/subsection_datafile.yml",
         trigger_datafile=f"{script_basepath}/trigger_datafile.yml",
         testbed=testbed,
         runtime=runtime,
         netbox=netbox
         )
