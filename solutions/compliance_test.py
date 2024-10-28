import logging
import json
import ipaddress
from genie.harness.base import Trigger
from pyats import aetest


# Set up logging
logger = logging.getLogger(__name__)


class TestDeviceCompliance(Trigger):
    @aetest.setup
    def prepare_test(self, uut, netbox):
        netbox_device = netbox.dcim.devices.get(name=uut.name)
        netbox_interface_records = netbox.dcim.interfaces.filter(device_id=netbox_device.id)
        netbox_interfaces = list(netbox_interface_records)

        parsed_interface_state = uut.parse("show interfaces")

        self.parameters.update(netbox_device=netbox_device,
                               netbox_interfaces=netbox_interfaces,
                               parsed_interface_state=parsed_interface_state)

        aetest.loop.mark(self.test_interfaces,
                         netbox_interface=netbox_interfaces)

    @aetest.test
    def test_interfaces(self,
                        steps,
                        netbox,
                        netbox_interface,
                        parsed_interface_state):
        # Get the op state for this interface
        interface_op_state = parsed_interface_state[netbox_interface.name]

        logger.info(
            "Current interface state data:\n%s",
            json.dumps(interface_op_state, indent=2)
        )

        # ARRANGE: Prepare desired and operational state for assertions

        # Desired state:
        desired_interface_state = netbox_interface.enabled
        desired_interface_description = netbox_interface.description
        desired_interface_ip = netbox.ipam.ip_addresses.get(interface_id=netbox_interface.id)

        # Operational state:
        ops_interface_state = interface_op_state.get("enabled", None)
        ops_interface_description = interface_op_state.get("description", None)

        if ops_ipv4_addresses := interface_op_state.get("ipv4", None):
            primary_address = next(iter(ops_ipv4_addresses))
            ops_interface_ipv4_address = ipaddress.IPv4Interface(primary_address)
        else:
            ops_interface_ipv4_address = None

        # ASSERT: Test desired vs op state for interface attributes

        with steps.start("Interface state", continue_=True):
            logger.info("Testing interface enable state: '%s'", desired_interface_state)
            assert desired_interface_state is ops_interface_state, \
                f"Interface operational state: {ops_interface_state}"

        with steps.start("Interface description", continue_=True):
            logger.info("Testing interface description: '%s'", desired_interface_description)
            assert desired_interface_description == ops_interface_description, \
                f"Interface operational description: {ops_interface_description}"

        with steps.start("Interface IPv4 Address", continue_=True):
            logger.info("Testing interface IPv4 address: %s", desired_interface_ip)
            assert str(desired_interface_ip) == str(ops_interface_ipv4_address), \
                f"Interface operational IPv4 address: {ops_interface_ipv4_address}"
