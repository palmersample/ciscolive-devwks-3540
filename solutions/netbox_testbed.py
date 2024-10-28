import logging
import json
import hvac
import pynetbox
from dotenv import dotenv_values
from pyats.topology import loader
from templates import testbed_device_template

logger = logging.getLogger(__name__)

config = dotenv_values("../workshop-env")

vault = hvac.Client(url=config["VAULT_URL"],
                    token=config["VAULT_TOKEN"])

try:
    netbox_secret = vault.secrets.kv.v2.read_secret_version(path="infra/netbox")
except hvac.exceptions.VaultError as err:
    raise RuntimeError("Failed to retrieve secret from Vault") from err


netbox = pynetbox.api(url=netbox_secret["data"]["data"]["netbox_url"],
                      token=netbox_secret["data"]["data"]["netbox_token"])


def add_device_to_testbed(netbox_device):
    if netbox_device.primary_ip4:
        vault_path = f"network/{netbox_device.name}"
        device_secret = vault.secrets.kv.v2.read_secret_version(vault_path)["data"]["data"]

        rendered_device = testbed_device_template.substitute(device_name=netbox_device.name,
                                                             device_os=netbox_device.platform.slug,
                                                             device_fqdn=netbox_device.primary_ip4.dns_name,
                                                             username=device_secret["username"],
                                                             password=device_secret["password"])

        device_data = json.loads(rendered_device)

    else:
        device_data = {}
    return device_data


def build_testbed(device_filter):
    testbed_dict = {"devices": {}}

    for device in netbox.dcim.devices.filter(**device_filter):
        testbed_dict["devices"].update(add_device_to_testbed(device))

    logger.info(json.dumps(testbed_dict, indent=2))

    testbed = loader.load(testbed_dict)
    return testbed
