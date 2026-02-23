from app.config import settings


def get_vless_config(server_ip: str) -> dict:
    """Возвращает параметры VLESS+Reality для клиента."""
    return {
        "protocol": "vless",
        "address": server_ip,
        "port": settings.XRAY_PORT,
        "uuid": settings.XRAY_UUID,
        "flow": "xtls-rprx-vision",
        "security": "reality",
        "reality_opts": {
            "public_key": settings.XRAY_PUBLIC_KEY,
            "short_id": settings.XRAY_SHORT_ID,
            "server_name": "www.microsoft.com",
            "fingerprint": "chrome",
        },
    }
