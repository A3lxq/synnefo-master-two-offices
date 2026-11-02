"""
Back Office — the branch's internal-only workstation. Flask, port 6000.
NEVER published by docker-compose.yml -- reachable only from inside the
frontdesk container (lateral movement / pivoting is the whole point).

INTENTIONALLY VULNERABLE: insecure deserialization (Python pickle) in
/api/process. A string-built shell command would be too on-the-nose
after Portside's command injection -- this teaches a different, very
real-world bug class instead.
"""
import base64
import os
import pickle
import sys

from flask import Flask, request, Response

sys.path.insert(0, "/opt/shared")
from generate_flags import flag_for  # noqa: E402

SECRET = os.environ["CTF_SECRET"]
app = Flask(__name__)


def flag(n):
    return flag_for(SECRET, n)


@app.route("/")
def index():
    return f"""Back Office internal tools API
------------------------------
note: {flag(6)}

POST base64-encoded pickled job data to /api/process.
"""


@app.route("/ops-portal")
def ops_portal_decoy():
    # Honeypot: a plausible internal path. The "ops" Linux account this
    # implies exists in /etc/passwd too, but has no valid path to it at
    # all -- it's not part of the intended chain.
    return "Ops portal is being migrated. Use the main API for now.\n"


@app.route("/api/process", methods=["POST"])
def process():
    data = request.form.get("data", "")
    try:
        obj = pickle.loads(base64.b64decode(data))
    except Exception as e:
        return Response(f"error: {e}\n", status=400)
    return Response(f"processed: {obj!r}\n")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=6000)
