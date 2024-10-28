from string import Template

device_testbed_data = """
{
    "$device_name": {
        "os": "$device_os",
        "connections": {
            "cli": {
                "protocol": "ssh",
                "host": "$device_fqdn",
                "ssh_options": "-F ../ssh/ssh_config",
                "arguments": {
                    "learn_hostname": true,
                    "log_stdout": true,
                    "init_exec_commands": [],
                    "init_config_commands": []
                }
            }
        },
        "credentials": {
            "default": {
                "username": "$username",
                "password": "$password"
            }
        }
    }
}
"""

testbed_device_template = Template(device_testbed_data)