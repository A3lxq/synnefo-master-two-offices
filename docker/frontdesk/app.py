"""
Front Desk — the regional branch's public-facing workstation. Flask,
port 5000 (published). INTENTIONALLY VULNERABLE: XXE in the schedule
importer. This host also serves final.enc from the very start (teased
upfront) -- it can't be decrypted until you've rooted BOTH hosts in this
box and combined what each one gives you.
"""
import os
import sys

from flask import Flask, request, Response
from lxml import etree

sys.path.insert(0, "/opt/shared")
from generate_flags import flag_for  # noqa: E402

SECRET = os.environ["CTF_SECRET"]
app = Flask(__name__)


def flag(n):
    return flag_for(SECRET, n)


@app.route("/")
def index():
    return f"""<!DOCTYPE html><html><head><title>Front Desk</title></head><body>
    <!-- {flag(1)} -->
    <h1>Halcyon Regional Branch — Front Desk</h1>
    <!-- staff login at /login, schedule importer at /import-schedule -->
    <p>Everything your branch needs, in one portal. See
    <a href="/final.enc">final.enc</a> — the last piece of this case file,
    available from day one. You'll need more than this page to open it.</p>
    </body></html>"""


@app.route("/login", methods=["GET", "POST"])
def login():
    error = ""
    if request.method == "POST":
        u = request.form.get("username", "")
        p = request.form.get("password", "")
        # INTENTIONALLY WEAK: real, working default creds, no injection needed.
        if u == "branch_staff" and p == "branch2024":
            return f"<h2>Welcome back.</h2><p>{flag(2)}</p>"
        error = "Invalid credentials."
    return f"""<!DOCTYPE html><html><body>
    <h2>Staff Login</h2>
    <p style="color:red">{error}</p>
    <form method="post">
      Username: <input name="username"><br>
      Password: <input name="password" type="password"><br>
      <button type="submit">Log in</button>
    </form></body></html>"""


@app.route("/import-schedule", methods=["GET", "POST"])
def import_schedule():
    if request.method == "GET":
        return """<!DOCTYPE html><html><body>
        <h2>Import Shipment Schedule (XML)</h2>
        <p>POST raw XML as the request body, Content-Type: application/xml.
        Example: &lt;schedule&gt;&lt;name&gt;Week 12&lt;/name&gt;&lt;/schedule&gt;</p>
        </body></html>"""
    # INTENTIONALLY VULNERABLE: classic XXE. External entities and DTDs
    # are explicitly enabled here, with no allowlist on what a <!ENTITY>
    # can point at.
    parser = etree.XMLParser(resolve_entities=True, no_network=False, load_dtd=True)
    try:
        tree = etree.fromstring(request.data, parser)
        name = tree.findtext("name") or "(no name field)"
        return Response(f"Schedule imported: {name}\n", mimetype="text/plain")
    except Exception as e:
        return Response(f"Import failed: {e}\n", status=400, mimetype="text/plain")


@app.route("/admin")
def admin_decoy():
    # Honeypot: a plausible path, nothing behind it.
    return Response("Not implemented yet. Ticket IT-2290.\n", status=501)


@app.route("/final.enc")
def final_enc():
    try:
        with open("/opt/frontdesk/final.enc", "rb") as f:
            return Response(f.read(), mimetype="application/octet-stream")
    except Exception as e:
        return Response(f"not ready: {e}", status=404)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
