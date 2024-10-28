import logging
import json
import ipaddress
from genie.harness.base import Trigger
from pyats import aetest


# Set up logging
logger = logging.getLogger(__name__)


class TestDeviceCompliance(Trigger):
