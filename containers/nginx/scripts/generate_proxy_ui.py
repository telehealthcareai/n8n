"""Generate proxy configuration."""

from __future__ import annotations

import os

from pathlib import Path
from typing import cast

from dotenv import load_dotenv
from jinja2 import Environment, FileSystemLoader

env_dir = Path("__file__").resolve().parent
load_dotenv(env_dir / ".envs" / ".env")

ENV = os.environ.get("ENV", "prod")
DOMAIN_ENV = os.environ.get("CERTBOT_DOMAIN")

print(f"Generating nginx config for: {DOMAIN_ENV}...")  # noqa: T201

# Set up Jinja2 environment
templates = Environment(
    loader=FileSystemLoader(Path(__file__).parent.parent / "templates"),
    autoescape=True,
)

nginx_template = templates.get_template("nginx.template.conf")
domains = cast(str, os.environ.get("CERTBOT_DOMAIN", ""))

# Define variables for the template
variables = {
    "upstream_name": "webapp",
    "upstream_service": "thcai-n8n",  # container hostname
    "upstream_port": os.environ.get("FRONTEND_HOST_PORT", 8000),
    "certbot_root": "/var/www/certbot",
    "letsencrypt_root": "/etc/letsencrypt",
    "domain": domains.split(",")[0],  # Prevents www.
}

# Render the template with variables
output = nginx_template.render(variables)

nginx_dir = Path(__file__).parent.parent / "data" / "config" / ENV

nginx_dir.mkdir(parents=True, exist_ok=True)

output_file = nginx_dir / f"{DOMAIN_ENV[:-4]}.nginx.conf"

output_file.write_text(output)
