import logging
import os
from dotenv import dotenv_values
from genie.harness.main import gRun
from netbox_testbed import netbox, build_testbed

logger = logging.getLogger()

script_basepath = os.path.dirname(__file__)
project_root = os.path.join(script_basepath, "..")
config = dotenv_values(f"{project_root}/workshop-env")

