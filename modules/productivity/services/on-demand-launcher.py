#!/usr/bin/env python3
import html
import hmac
import hashlib
import json
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


HTTP_OPENER = urllib.request.build_opener(NoRedirectHandler)
ACTION_LOCK = threading.Lock()


def load_config():
    if len(sys.argv) != 2:
        print("usage: on-demand-apps-dashboard.py CONFIG", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], "r", encoding="utf-8") as config_file:
        return json.load(config_file)


CONFIG = load_config()
APPS = {app["id"]: app for app in CONFIG["apps"]}
CSRF_SECRET = os.urandom(32)
STATUS_LABELS = {
    "failed": "Needs attention",
    "running": "Live",
    "starting": "Starting",
    "stopped": "Stopped",
}
STATUS_RING_LABELS = {
    "failed": "ALERT",
    "running": "READY",
    "starting": "WAIT",
    "stopped": "IDLE",
    "stopping": "STOP",
}
STATE_CAPTIONS = {
    "failed": "Startup needs attention",
    "running": "Ready to open",
    "starting": "Starting and checking health",
    "stopped": "Idle and offline",
    "stopping": "Stopping and releasing resources",
}
INTERACTION_SCRIPT = r"""
(() => {
  const POLL_MS = 1600;
  const OPEN_DELAY_MS = 700;
  const MAX_POLLS = 120;
  const STATUS_LABELS = {
    failed: "Needs attention",
    running: "Live",
    starting: "Starting",
    stopping: "Stopping",
    stopped: "Stopped",
  };
  const STATUS_RING_LABELS = {
    failed: "ALERT",
    running: "READY",
    starting: "WAIT",
    stopping: "STOP",
    stopped: "IDLE",
  };
  const STATE_CAPTIONS = {
    failed: "Startup needs attention",
    running: "Ready to open",
    starting: "Starting and checking health",
    stopping: "Stopping and releasing resources",
    stopped: "Idle and offline",
  };
  const STAGE_TEXT = {
    error: "Action failed",
    health: "Waiting for health check",
    ready: "Ready",
    request: "Sending request",
    stopping: "Stopping systemd units",
    units: "Starting systemd units",
  };

  function statusLabel(status) {
    return STATUS_LABELS[status] || String(status || "").toUpperCase();
  }

  function statusRingLabel(status) {
    return STATUS_RING_LABELS[status] || statusLabel(status);
  }

  function sleep(ms) {
    return new Promise((resolve) => window.setTimeout(resolve, ms));
  }

  function appPanel(node) {
    return node.closest("[data-app-card]");
  }

  function setText(panel, selector, value) {
    const element = panel.querySelector(selector);
    if (element) {
      element.textContent = value;
    }
  }

  function setButtonLabel(button, value) {
    const label = button.querySelector(".button-label");
    if (label) {
      label.textContent = value;
    }
  }

  function setButtonBusy(form, busy) {
    const button = form.querySelector("button");
    if (!button) {
      return;
    }
    const label = button.querySelector(".button-label");
    if (busy) {
      button.classList.add("is-busy");
      button.disabled = true;
      if (label && button.dataset.loadingLabel) {
        label.textContent = button.dataset.loadingLabel;
      }
      return;
    }
    button.classList.remove("is-busy");
    if (label && button.dataset.defaultLabel) {
      label.textContent = button.dataset.defaultLabel;
    }
  }

  function setControls(panel, status, busy) {
    const blocked = Boolean(status.blocked && status.blocked.length);
    const state = status.status || panel.dataset.status || "stopped";
    panel.querySelectorAll("[data-start-action]").forEach((element) => {
      element.hidden = state === "running" || state === "stopping";
    });
    panel.querySelectorAll("[data-open-action]").forEach((element) => {
      element.hidden = state !== "running" || busy;
    });
    panel.querySelectorAll("[data-stop-action]").forEach((element) => {
      element.hidden = state === "stopped";
    });
    panel.querySelectorAll("[data-action-form]").forEach((form) => {
      const button = form.querySelector("button");
      if (!button) {
        return;
      }
      const action = form.dataset.action;
      if (busy) {
        button.disabled = true;
      } else if (action === "start") {
        button.disabled = blocked || state === "starting" || state === "running" || state === "stopping";
      } else if (action === "stop") {
        button.disabled = blocked || state === "stopped";
      }
      if (!busy) {
        setButtonBusy(form, false);
        if (action === "start" && state === "starting") {
          setButtonLabel(button, "Starting");
        } else if (button.dataset.defaultLabel) {
          setButtonLabel(button, button.dataset.defaultLabel);
        }
      }
    });
  }

  function setStateFlow(panel, status) {
    panel.querySelectorAll("[data-role='state-flow']").forEach((flow) => {
      flow.className = `state-flow ${status.status}`;
      flow.dataset.status = status.status;
      flow.setAttribute("aria-label", `Current state: ${statusLabel(status.status)}`);
    });
    setText(panel, "[data-role='state-copy']", STATE_CAPTIONS[status.status] || statusLabel(status.status));
  }

  function setDocumentText(selector, value) {
    document.querySelectorAll(selector).forEach((element) => {
      element.textContent = value;
    });
  }

  function updateDashboardSummary() {
    const panels = Array.from(document.querySelectorAll("[data-app-card]"));
    if (!panels.length) {
      return;
    }
    const totals = panels.reduce(
      (summary, panel) => {
        const state = panel.dataset.status || "stopped";
        if (state === "running") {
          summary.running += 1;
        } else if (state === "stopped") {
          summary.stopped += 1;
        }
        summary.safety = Math.max(summary.safety, Number(panel.dataset.blockedCount || 0));
        return summary;
      },
      { running: 0, safety: 0, stopped: 0 }
    );
    setDocumentText("[data-summary='running']", String(totals.running));
    setDocumentText("[data-summary='stopped']", String(totals.stopped));
    setDocumentText("[data-summary='safety']", String(totals.safety));
    setDocumentText("[data-summary='total']", String(panels.length));
    setDocumentText(
      "[data-summary='hero-copy']",
      `${totals.running} running / ${totals.stopped} stopped / ${totals.safety} safety locks`
    );
  }

  function showActivity(panel, message, stage, title = "Working", mode = "start") {
    const activity = panel.querySelector("[data-activity-panel]");
    if (!activity) {
      return;
    }
    activity.hidden = false;
    activity.dataset.mode = mode;
    activity.dataset.stage = stage;
    panel.classList.add("is-launching");
    panel.setAttribute("aria-busy", "true");
    setText(panel, "[data-activity-title]", title);
    setText(panel, "[data-activity-stage]", STAGE_TEXT[stage] || statusLabel(stage));
    setText(panel, "[data-activity-message]", message);
  }

  function hideActivity(panel) {
    const activity = panel.querySelector("[data-activity-panel]");
    if (activity) {
      activity.hidden = true;
    }
    panel.classList.remove("is-launching");
    panel.removeAttribute("aria-busy");
  }

  function phaseMessage(status) {
    if (status.status === "running") {
      return "Live. Opening the app.";
    }
    if (status.status === "starting") {
      return "Starting. Waiting for the health check.";
    }
    if (status.status === "failed") {
      return "Startup needs attention. Check the systemd state below.";
    }
    return "Start request accepted. Waiting for systemd.";
  }

  function phaseStage(status) {
    if (status.status === "running") {
      return "ready";
    }
    if (status.status === "starting") {
      return "health";
    }
    if (status.status === "failed") {
      return "error";
    }
    return "units";
  }

  function updatePanel(panel, status, busy = false) {
    panel.dataset.status = status.status;
    panel.dataset.blockedCount = String(status.blocked ? status.blocked.length : Number(panel.dataset.blockedCount || 0));
    const chip = panel.querySelector("[data-role='status-chip']");
    if (chip) {
      chip.className = `status ${status.status}`;
      chip.textContent = statusLabel(status.status);
    }
    const statusRing = panel.querySelector("[data-role='status-ring']");
    if (statusRing) {
      statusRing.dataset.value = statusRingLabel(status.status);
    }
    const active = status.active_units ?? Number(panel.dataset.activeUnits || 0);
    const total = status.unit_count ?? (status.units ? Object.keys(status.units).length : Number(panel.dataset.unitCount || 0));
    panel.dataset.activeUnits = String(active);
    panel.dataset.unitCount = String(total);
    setText(panel, "[data-role='unit-count']", `${active}/${total} units active`);
    setText(panel, "[data-role='health']", statusLabel(status.status));
    setText(panel, "[data-role='safety']", status.blocked && status.blocked.length ? "Locked" : "Clear");
    setStateFlow(panel, status);
    setControls(panel, status, busy);
    updateDashboardSummary();
  }

  async function fetchStatus(appId) {
    const response = await fetch(`/apps/${encodeURIComponent(appId)}/status`, {
      credentials: "same-origin",
      headers: { Accept: "application/json" },
    });
    if (!response.ok) {
      throw new Error(`Status request failed with HTTP ${response.status}`);
    }
    return response.json();
  }

  async function pollUntil(appId, panel, target) {
    let latestStatus = null;
    for (let attempt = 0; attempt < MAX_POLLS; attempt += 1) {
      await sleep(POLL_MS);
      const status = await fetchStatus(appId);
      latestStatus = status;
      updatePanel(panel, status, true);
      if (target === "running") {
        showActivity(panel, phaseMessage(status), phaseStage(status), "Starting app", "start");
        if (status.status === "running") {
          window.setTimeout(() => {
            window.location.assign(status.url);
          }, OPEN_DELAY_MS);
          return;
        }
        if (status.status === "failed") {
          setControls(panel, status, false);
          return;
        }
      } else if (target === "stopped") {
        if (status.status === "stopped") {
          updatePanel(panel, status, false);
          showActivity(panel, "Stopped. The app is idle.", "ready", "Stopped", "stop");
          window.setTimeout(() => {
            hideActivity(panel);
          }, 900);
          return;
        }
        showActivity(panel, "Stopping app. Waiting for systemd state.", "stopping", "Stopping app", "stop");
      }
    }
    if (latestStatus) {
      updatePanel(panel, latestStatus, false);
    }
    showActivity(panel, "Still waiting. Refresh for the latest systemd state.", target === "running" ? "health" : "stopping", "Still working", target === "running" ? "start" : "stop");
  }

  async function submitAction(event) {
    const form = event.target.closest("[data-action-form]");
    if (!form || !window.fetch || !window.FormData || !window.URLSearchParams) {
      return;
    }
    event.preventDefault();
    const panel = appPanel(form);
    if (!panel) {
      form.submit();
      return;
    }
    const appId = form.dataset.appId;
    const action = form.dataset.action;
    const target = action === "start" ? "running" : "stopped";
    if (action === "start") {
      updatePanel(panel, { status: "starting", blocked: [] }, true);
    } else {
      updatePanel(panel, { status: "stopping", blocked: [] }, true);
    }
    setButtonBusy(form, true);
    showActivity(
      panel,
      action === "start" ? "Sending start request." : "Sending stop request.",
      "request",
      action === "start" ? "Starting app" : "Stopping app",
      action === "start" ? "start" : "stop"
    );
    try {
      const response = await fetch(form.action, {
        method: "POST",
        body: new URLSearchParams(new FormData(form)),
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
          "X-Requested-With": "fetch",
        },
      });
      const payload = await response.json();
      if (payload.status) {
        updatePanel(panel, payload.status, true);
      }
      if (!response.ok || !payload.ok) {
        throw new Error(payload.error || `Request failed with HTTP ${response.status}`);
      }
      showActivity(
        panel,
        action === "start"
          ? "Systemd accepted the start request."
          : "Systemd accepted the stop request.",
        action === "start" ? "units" : "stopping",
        action === "start" ? "Starting app" : "Stopping app",
        action === "start" ? "start" : "stop"
      );
      await pollUntil(appId, panel, target);
    } catch (error) {
      const status = await fetchStatus(appId).catch(() => null);
      if (status) {
        updatePanel(panel, status, false);
      }
      showActivity(panel, error.message || "Action failed.", "error", "Action failed", action === "start" ? "start" : "stop");
      if (status) {
        setControls(panel, status, false);
      }
    } finally {
      setButtonBusy(form, false);
    }
  }

  document.addEventListener("submit", submitAction);
  document.querySelectorAll("[data-app-card][data-status='starting']").forEach((panel) => {
    showActivity(panel, "Starting. Waiting for the health check.", "health", "Starting app", "start");
  });
})();
"""


def esc(value):
    return html.escape(str(value), quote=True)

def status_label(status):
    return STATUS_LABELS.get(status, status.upper())


def status_ring_label(status):
    return STATUS_RING_LABELS.get(status, status_label(status))


def active_unit_count(status):
    return sum(
        1
        for state in status["units"].values()
        if state["ActiveState"] in {"active", "activating", "reloading"}
    )


def state_caption(status):
    return STATE_CAPTIONS.get(status, status_label(status))


def render_state_flow(status, include_copy=True):
    current = status["status"]
    copy_html = (
        f'\n  <div class="state-copy" data-role="state-copy">{esc(state_caption(current))}</div>'
        if include_copy
        else ""
    )
    return f"""<div class="state-flow {esc(current)}" data-role="state-flow" data-status="{esc(current)}" aria-label="Current state: {esc(status_label(current))}">
  <div class="state-rail" aria-hidden="true">
    <span class="state-fill"></span>
    <span class="state-node node-stopped"></span>
    <span class="state-node node-starting"></span>
    <span class="state-node node-running"></span>
  </div>
  <div class="state-labels">
    <span>Stopped</span>
    <span>Starting</span>
    <span>Live</span>
  </div>
  {copy_html}
</div>"""


def render_unit_grid(status):
    rows = []
    for unit, state in status["units"].items():
        rows.append(
            f"""<div class="unit-row">
  <div class="unit-name">{esc(unit)}</div>
  <div class="unit-state">{esc(state["LoadState"])} / {esc(state["ActiveState"])} / {esc(state["SubState"])}</div>
  <div class="unit-result">{esc(state["Result"])}</div>
</div>"""
        )
    return "".join(rows) or '<div class="unit-row"><div class="unit-name">No units declared</div></div>'


def render_actions(app, status, user, compact=False):
    blocked = bool(status["blocked"])
    start_disabled = " disabled" if blocked or status["status"] == "starting" else ""
    stop_disabled = " disabled" if blocked or status["status"] == "stopped" else ""
    start_hidden = " hidden" if status["status"] == "running" else ""
    open_hidden = "" if status["status"] == "running" else " hidden"
    stop_hidden = " hidden" if status["status"] == "stopped" else ""
    detail_link = "" if not compact else f'<a class="button ghost" href="/apps/{esc(app["id"])}">Manage</a>'

    return f"""<div class="actions">
  <form method="post" action="/apps/{esc(app["id"])}/start" data-action-form data-action="start" data-app-id="{esc(app["id"])}" data-start-action{start_hidden}>
  <input type="hidden" name="csrf" value="{esc(csrf_token(user, app["id"], "start"))}">
  <button class="primary" type="submit" data-default-label="Start and open" data-loading-label="Starting"{start_disabled}>
    <span class="button-label">Start and open</span>
    <span class="spinner" aria-hidden="true"></span>
  </button>
</form>
  <a class="button primary" href="{esc(app["url"])}" data-open-action{open_hidden}>Open app</a>
  {detail_link}
  <form method="post" action="/apps/{esc(app["id"])}/stop" data-action-form data-action="stop" data-app-id="{esc(app["id"])}" data-stop-action{stop_hidden}>
    <input type="hidden" name="csrf" value="{esc(csrf_token(user, app["id"], "stop"))}">
    <button class="secondary danger-action" type="submit" data-default-label="Stop app" data-loading-label="Stopping"{stop_disabled}>
      <span class="button-label">Stop app</span>
      <span class="spinner" aria-hidden="true"></span>
    </button>
  </form>
</div>"""


def render_activity(status):
    hidden = "" if status["status"] == "starting" else " hidden"
    title = "Starting app" if status["status"] == "starting" else "Working"
    message = (
        "Starting. Waiting for the health check."
        if status["status"] == "starting"
        else "Ready for action."
    )
    stage = "Waiting for health check" if status["status"] == "starting" else "Ready"
    return f"""<div class="activity" data-mode="start" data-stage="health"{hidden} data-activity-panel aria-live="polite">
  <span class="activity-spinner" aria-hidden="true"></span>
  <div class="activity-copy">
    <div class="activity-head">
      <span class="label" data-activity-title>{esc(title)}</span>
      <span class="activity-stage" data-activity-stage>{esc(stage)}</span>
    </div>
    <p data-activity-message>{esc(message)}</p>
  </div>
</div>"""


def csrf_token(user, app_id, action):
    subject = "\0".join([user or "", app_id, action]).encode("utf-8")
    return hmac.new(CSRF_SECRET, subject, hashlib.sha256).hexdigest()


def csrf_valid(user, app_id, action, token):
    expected = csrf_token(user, app_id, action)
    return hmac.compare_digest(expected, token or "")


def systemctl(*args, check=False):
    result = subprocess.run(
        ["systemctl", *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=240,
    )
    if check and result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip() or "systemctl failed"
        raise RuntimeError(message)
    return result


def reset_failed_units(units):
    seen = set()
    for unit in units:
        if unit in seen:
            continue
        seen.add(unit)
        if unit_state(unit)["ActiveState"] == "failed":
            systemctl("reset-failed", unit)


def unit_state(unit):
    result = systemctl(
        "show",
        unit,
        "--property=LoadState",
        "--property=ActiveState",
        "--property=SubState",
        "--property=Result",
        "--property=RemainAfterExit",
        "--property=Type",
        "--no-pager",
    )
    state = {
        "LoadState": "unknown",
        "ActiveState": "unknown",
        "SubState": "unknown",
        "Result": "unknown",
        "RemainAfterExit": "unknown",
        "Type": "unknown",
    }
    if result.returncode != 0:
        state["LoadState"] = "not-found"
        state["Error"] = result.stderr.strip() or result.stdout.strip()
        return state
    for line in result.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            state[key] = value
    return state


def unit_active_or_starting(unit):
    state = unit_state(unit)
    return state["ActiveState"] in {"active", "activating", "reloading"}


def unit_blocks_actions(state):
    if state["ActiveState"] in {"activating", "reloading", "deactivating"}:
        return True
    if state["ActiveState"] != "active":
        return False
    if (
        state["Type"] == "oneshot"
        and state["SubState"] == "exited"
        and state["Result"] in {"success", ""}
    ):
        return False
    return True


def blocking_reasons():
    reasons = []
    lock_path = CONFIG.get("maintenance_lock")
    if lock_path and os.path.exists(lock_path):
        try:
            with open(lock_path, "r", encoding="utf-8") as lock_file:
                reason = lock_file.read().strip()
        except OSError:
            reason = ""
        reasons.append(reason or f"{lock_path} exists")

    for unit in CONFIG.get("blocked_units", []):
        state = unit_state(unit)
        if unit_blocks_actions(state):
            reasons.append(f"{unit} is {state['ActiveState']}")
    return reasons


def health_ok(app):
    health = app.get("health", {})
    request = urllib.request.Request(
        health["url"],
        headers=health.get("headers", {}),
        method="GET",
    )
    ok_statuses = set(health.get("ok_statuses", [200]))
    timeout = float(health.get("request_timeout_seconds", 5))
    try:
        with HTTP_OPENER.open(request, timeout=timeout) as response:
            return response.status in ok_statuses
    except urllib.error.HTTPError as exc:
        return exc.code in ok_statuses
    except (OSError, TimeoutError, urllib.error.URLError):
        return False


def wait_for_health(app):
    deadline = time.monotonic() + float(app["health"].get("wait_seconds", 120))
    while time.monotonic() < deadline:
        if health_ok(app):
            return True
        time.sleep(float(app["health"].get("poll_seconds", 2)))
    return health_ok(app)


def app_status(app):
    units = {unit: unit_state(unit) for unit in app.get("status_units", [])}
    active_states = [state["ActiveState"] for state in units.values()]
    active_units = sum(
        1 for state in units.values() if state["ActiveState"] in {"active", "activating", "reloading"}
    )
    failed = any(state == "failed" for state in active_states) or any(
        state.get("Result") not in {"success", ""} and state["ActiveState"] == "failed"
        for state in units.values()
    )
    if failed:
        status = "failed"
    elif health_ok(app):
        status = "running"
    elif any(state in {"activating", "reloading", "active"} for state in active_states):
        status = "starting"
    else:
        status = "stopped"
    return {
        "active_units": active_units,
        "id": app["id"],
        "name": app["name"],
        "status": status,
        "unit_count": len(units),
        "url": app["url"],
        "units": units,
        "blocked": blocking_reasons(),
    }


def render_page(title, body, status=HTTPStatus.OK):
    return status, "text/html; charset=utf-8", f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{esc(title)}</title>
  <style>
    :root {{
      --bg: #101211;
      --panel: #141716;
      --panel-strong: #181c1b;
      --line: #313937;
      --line-bright: #53625e;
      --text: #f3f0c5;
      --muted: #a0aaa5;
      --dim: #68736f;
      --accent: #0a8fa3;
      --accent-bright: #16b2c8;
      --danger: #e5484d;
      --mono: "JetBrains Mono", var(--system-mono);
      --warn: #efe6a0;
      --ok: #8fcf9b;
      --system-mono: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      color-scheme: dark;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.45;
    }}
	    * {{
	      box-sizing: border-box;
	    }}
	    [hidden] {{
	      display: none !important;
	    }}
	    body {{
      margin: 0;
      min-height: 100vh;
      background:
        linear-gradient(rgba(255, 255, 255, 0.018) 1px, transparent 1px),
        linear-gradient(90deg, rgba(255, 255, 255, 0.014) 1px, transparent 1px),
        var(--bg);
      background-size: 48px 48px;
      color: var(--text);
    }}
    main {{
      width: min(1180px, calc(100% - 28px));
      margin: 22px auto 36px;
    }}
	    .topbar {{
	      display: flex;
	      align-items: center;
	      justify-content: space-between;
      gap: 12px;
      border: 1px solid var(--line);
      background: rgba(20, 23, 22, 0.94);
      min-height: 48px;
	      padding: 12px 16px;
	      margin-bottom: 14px;
	    }}
	    .brand {{
	      display: flex;
	      align-items: center;
	      min-width: 0;
	      text-decoration: none;
	    }}
		    .brand-name {{
		      color: var(--text);
		      font-family: var(--mono);
		      font-size: 0.88rem;
		      font-weight: 800;
	      letter-spacing: 0;
	      overflow: hidden;
	      text-overflow: ellipsis;
		      text-transform: uppercase;
		      white-space: nowrap;
	    }}
	    .topbar-meta {{
	      color: var(--muted);
	      font-family: var(--mono);
	      font-size: 0.72rem;
	      font-weight: 800;
	      letter-spacing: 0;
	      text-transform: uppercase;
	      white-space: nowrap;
	    }}
    h1, h2, h3, p {{
      margin: 0;
    }}
    a {{
      color: inherit;
    }}
	    .eyebrow, .label {{
	      color: var(--accent-bright);
	      font-family: var(--mono);
	      font-size: 0.72rem;
	      font-weight: 800;
	      letter-spacing: 0;
	      text-transform: uppercase;
	    }}
    .muted {{
      color: var(--muted);
      font-size: 0.92rem;
    }}
    .dashboard {{
      display: grid;
      gap: 14px;
    }}
    .hero {{
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 16px;
      min-height: 176px;
      padding: 20px;
    }}
    .panel {{
      border: 1px solid var(--line);
      background: rgba(20, 23, 22, 0.94);
    }}
    .panel-header {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      min-height: 46px;
      border-bottom: 1px solid var(--line);
      padding: 12px 16px;
    }}
    .panel-body {{
      padding: 16px;
    }}
	    .hero h1 {{
	      max-width: 760px;
	      margin-top: 10px;
	      color: var(--text);
	      font-family: var(--mono);
	      font-size: 3.4rem;
	      font-weight: 500;
	      letter-spacing: 0;
	      line-height: 1.05;
	      text-transform: uppercase;
	    }}
    .hero-copy {{
      max-width: 760px;
      margin-top: 14px;
      color: var(--muted);
    }}
    .hero-metric {{
      align-self: center;
      justify-self: end;
      text-align: right;
      white-space: nowrap;
    }}
	    .hero-number {{
	      color: var(--text);
	      font-family: var(--mono);
	      font-size: 7rem;
	      font-weight: 300;
	      line-height: 0.9;
	    }}
    .hero-number small {{
      color: var(--accent);
      font-size: 0.35em;
    }}
    .hero-caption {{
      margin-top: 8px;
	      color: var(--muted);
	      font-family: var(--mono);
	      font-size: 0.72rem;
	      letter-spacing: 0;
	      text-transform: uppercase;
	    }}
    .row {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      flex-wrap: wrap;
    }}
    .summary-grid {{
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 14px;
    }}
    .summary-tile {{
      min-height: 116px;
      border: 1px solid var(--line);
      background: var(--panel-strong);
      padding: 14px;
    }}
    .summary-value {{
      margin-top: 10px;
      color: var(--text);
      font-family: var(--mono);
      font-size: 3.4rem;
      font-weight: 300;
      line-height: 1;
    }}
    .app-grid {{
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 14px;
    }}
    .app-card {{
      display: grid;
      grid-template-rows: auto 1fr auto;
      gap: 14px;
      min-height: 390px;
      border: 1px solid var(--line);
      background: var(--panel);
      padding: 18px;
    }}
    .app-title {{
	      color: var(--text);
	      font-family: var(--mono);
	      font-size: 1.1rem;
	      font-weight: 700;
	      letter-spacing: 0;
	      text-transform: uppercase;
	    }}
	    .status {{
	      display: inline-flex;
	      align-items: center;
	      gap: 8px;
	      min-height: 28px;
	      border: 1px solid var(--line);
	      background: rgba(104, 115, 111, 0.08);
	      padding: 4px 10px;
		      color: var(--muted);
	      font-family: var(--mono);
	      font-size: 0.72rem;
	      font-weight: 800;
	      letter-spacing: 0;
	      text-transform: uppercase;
	      white-space: nowrap;
		    }}
	    .status::before {{
	      content: "";
	      width: 8px;
	      height: 8px;
	      border-radius: 50%;
	      background: currentColor;
	      box-shadow: 0 0 0 3px rgba(255, 255, 255, 0.04);
	    }}
		    .status.stopped {{
		      border-color: rgba(104, 115, 111, 0.48);
		      background: rgba(104, 115, 111, 0.08);
		      color: var(--muted);
		    }}
		    .status.running {{
		      border-color: rgba(143, 207, 155, 0.48);
		      background: rgba(143, 207, 155, 0.1);
		      color: var(--ok);
	    }}
	    .status.starting {{
	      border-color: rgba(239, 230, 160, 0.5);
	      background: rgba(239, 230, 160, 0.1);
	      color: var(--warn);
	    }}
	    .status.stopping {{
	      border-color: rgba(239, 230, 160, 0.5);
	      background: rgba(239, 230, 160, 0.08);
	      color: var(--warn);
	    }}
	    .status.failed {{
	      border-color: rgba(229, 72, 77, 0.52);
	      background: rgba(229, 72, 77, 0.08);
	      color: var(--danger);
	    }}
    .status-ring {{
      display: grid;
      place-items: center;
      width: 70px;
      height: 70px;
      border: 1px solid rgba(83, 98, 94, 0.72);
      background:
        conic-gradient(currentColor 0deg, rgba(104, 115, 111, 0.18) 0),
        rgba(20, 23, 22, 0.82);
      border-radius: 50%;
      color: var(--dim);
    }}
    .status-ring::after {{
      content: attr(data-value);
      display: grid;
      place-items: center;
      width: 46px;
      height: 46px;
      border: 1px solid var(--line);
      background: var(--panel);
      border-radius: 50%;
      color: var(--text);
      font-family: var(--mono);
      font-size: 0.72rem;
      font-weight: 800;
    }}
    .app-card[data-status="running"] .status-ring {{
      background:
        conic-gradient(var(--ok) 360deg, rgba(104, 115, 111, 0.18) 0),
        rgba(20, 23, 22, 0.82);
      color: var(--ok);
    }}
    .app-card[data-status="starting"] .status-ring,
    .app-card[data-status="stopping"] .status-ring {{
      background:
        conic-gradient(var(--warn) 180deg, rgba(104, 115, 111, 0.18) 0),
        rgba(20, 23, 22, 0.82);
      color: var(--warn);
    }}
    .app-card[data-status="failed"] .status-ring {{
      background:
        conic-gradient(var(--danger) 180deg, rgba(104, 115, 111, 0.18) 0),
        rgba(20, 23, 22, 0.82);
      color: var(--danger);
    }}
    .state-summary {{
      display: grid;
      gap: 7px;
      min-height: 30px;
      position: relative;
    }}
    .state-summary .status {{
      width: fit-content;
    }}
    .state-summary p {{
      position: absolute;
      top: calc(100% + 8px);
      left: 0;
      z-index: 10;
      width: min(320px, 100%);
      border: 1px solid var(--line-bright);
      background: rgba(16, 18, 17, 0.98);
      box-shadow: 0 14px 28px rgba(0, 0, 0, 0.32);
      color: var(--muted);
      font-size: 0.78rem;
      line-height: 1.35;
      opacity: 0;
      padding: 9px 10px;
      pointer-events: none;
      transform: translateY(-3px);
      transition: opacity 140ms ease, transform 140ms ease;
    }}
    .state-summary .status:hover + p,
    .state-summary .status:focus + p,
    .state-summary .status:focus-visible + p {{
      opacity: 1;
      transform: translateY(0);
    }}
    .card-mid {{
      display: grid;
      gap: 14px;
      align-content: start;
    }}
    .quick-stats {{
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      border: 1px solid var(--line);
      background: rgba(24, 28, 27, 0.66);
    }}
    .quick-stat {{
      display: grid;
      gap: 4px;
      min-width: 0;
      padding: 9px;
      border-right: 1px solid var(--line);
    }}
    .quick-stat:last-child {{
      border-right: 0;
    }}
    .quick-stat span {{
      color: var(--muted);
      font-family: var(--mono);
      font-size: 0.65rem;
      font-weight: 800;
      letter-spacing: 0;
      text-transform: uppercase;
    }}
    .quick-stat strong {{
      color: var(--text);
      font-family: var(--mono);
      font-size: 0.82rem;
      font-weight: 800;
      overflow-wrap: anywhere;
      text-transform: uppercase;
    }}
	    .state-flow {{
	      display: grid;
	      gap: 10px;
	      border: 1px solid var(--line);
	      background:
          linear-gradient(180deg, rgba(255, 255, 255, 0.026), transparent 42%),
          rgba(24, 28, 27, 0.72);
	      padding: 14px 16px 12px;
	    }}
	    .state-rail {{
	      position: relative;
	      height: 32px;
	      margin: 0 7px;
	    }}
	    .state-rail::before, .state-fill {{
	      content: "";
	      position: absolute;
	      top: 50%;
	      left: 0;
	      right: 0;
	      height: 4px;
	      transform: translateY(-50%);
	    }}
	    .state-rail::before {{
	      background: rgba(104, 115, 111, 0.28);
	      box-shadow: 0 0 0 1px rgba(104, 115, 111, 0.10);
	    }}
	    .state-fill {{
	      right: auto;
	      width: 0;
	      background: var(--accent-bright);
	      box-shadow: 0 0 10px rgba(22, 178, 200, 0.20);
	      transition: width 360ms ease, background 180ms ease;
	    }}
	    .state-flow.stopped .state-fill {{
	      width: 0;
	      background: var(--dim);
	      box-shadow: none;
	    }}
	    .state-flow.starting .state-fill, .state-flow.stopping .state-fill {{
	      width: 50%;
	      background: var(--warn);
	      box-shadow: 0 0 12px rgba(239, 230, 160, 0.22);
	    }}
	    .state-flow.running .state-fill {{
	      width: 100%;
	      background: var(--ok);
	      box-shadow: 0 0 12px rgba(143, 207, 155, 0.22);
	    }}
	    .state-flow.failed .state-fill {{
	      width: 50%;
	      background: var(--danger);
	      box-shadow: 0 0 12px rgba(229, 72, 77, 0.20);
	    }}
	    .state-node {{
	      position: absolute;
	      top: 50%;
	      width: 16px;
	      height: 16px;
	      border: 2px solid var(--line-bright);
	      border-radius: 50%;
	      background: var(--panel);
	      transform: translate(-50%, -50%);
	      box-shadow:
          0 0 0 4px rgba(16, 18, 17, 0.82),
          0 0 0 5px rgba(83, 98, 94, 0.18);
	      transition: background 180ms ease, border-color 180ms ease, box-shadow 180ms ease;
	    }}
	    .node-stopped {{
	      left: 0;
	    }}
	    .node-starting {{
	      left: 50%;
	    }}
	    .node-running {{
	      left: 100%;
	    }}
	    .state-flow.stopped .node-stopped,
	    .state-flow.starting .node-starting,
	    .state-flow.stopping .node-starting,
	    .state-flow.running .node-running,
	    .state-flow.failed .node-starting {{
	      background: currentColor;
	      border-color: currentColor;
	      box-shadow:
          0 0 0 4px rgba(16, 18, 17, 0.82),
          0 0 0 6px rgba(255, 255, 255, 0.05),
          0 0 16px rgba(255, 255, 255, 0.10);
	    }}
	    .state-flow.starting .node-stopped,
	    .state-flow.stopping .node-stopped,
	    .state-flow.running .node-stopped,
	    .state-flow.running .node-starting {{
	      border-color: currentColor;
	      background: rgba(24, 28, 27, 0.92);
	    }}
	    .state-flow.running {{
	      color: var(--ok);
	    }}
	    .state-flow.starting, .state-flow.stopping {{
	      color: var(--warn);
	    }}
	    .state-flow.failed {{
	      color: var(--danger);
	    }}
	    .state-flow.stopped {{
	      color: var(--muted);
	    }}
	    .state-labels {{
	      display: grid;
	      grid-template-columns: repeat(3, minmax(0, 1fr));
	      gap: 10px;
	      color: var(--muted);
	      font-family: var(--mono);
	      font-size: 0.68rem;
	      font-weight: 800;
	      letter-spacing: 0;
	      line-height: 1.15;
	      text-transform: uppercase;
	    }}
	    .state-labels span:nth-child(2) {{
	      text-align: center;
	    }}
	    .state-labels span:nth-child(3) {{
	      text-align: right;
	    }}
	    .state-flow.stopped .state-labels span:nth-child(1),
	    .state-flow.starting .state-labels span:nth-child(2),
	    .state-flow.stopping .state-labels span:nth-child(2),
	    .state-flow.running .state-labels span:nth-child(3),
	    .state-flow.failed .state-labels span:nth-child(2) {{
	      color: var(--text);
	    }}
	    .state-copy {{
	      color: var(--text);
	      font-size: 0.92rem;
	    }}
    .actions {{
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }}
	    button, .button {{
	      appearance: none;
	      display: inline-flex;
	      align-items: center;
	      justify-content: center;
	      gap: 9px;
	      border: 1px solid var(--line-bright);
	      background: #26312e;
	      color: var(--text);
      cursor: pointer;
	      font-family: var(--mono);
	      font-size: 0.78rem;
	      font-weight: 800;
	      letter-spacing: 0;
	      min-height: 42px;
	      padding: 9px 14px;
	      text-decoration: none;
	      text-transform: uppercase;
	      transition:
	        background 160ms ease,
	        border-color 160ms ease,
	        color 160ms ease,
	        transform 160ms ease;
	    }}
	    button:hover:not(:disabled), .button:hover {{
	      transform: translateY(-1px);
	    }}
	    button:focus-visible, .button:focus-visible {{
	      outline: 2px solid var(--accent-bright);
	      outline-offset: 2px;
	    }}
	    button.primary, .button.primary {{
	      border-color: rgba(22, 178, 200, 0.9);
	      background: var(--accent);
      color: #071112;
    }}
	    button.secondary, .button.secondary, .button.ghost {{
	      background: transparent;
	      color: var(--muted);
	    }}
	    button.danger-action:not(:disabled) {{
	      border-color: rgba(229, 72, 77, 0.58);
	      color: #ffb3b5;
	    }}
	    button:disabled {{
	      cursor: not-allowed;
	      opacity: 0.55;
	    }}
	    button.is-busy {{
	      opacity: 0.95;
	    }}
	    .spinner {{
	      display: none;
	      width: 14px;
	      height: 14px;
	      border: 2px solid rgba(7, 17, 18, 0.34);
	      border-top-color: currentColor;
	      border-radius: 50%;
	      animation: spin 780ms linear infinite;
	    }}
	    button.secondary .spinner {{
	      border-color: rgba(160, 170, 165, 0.22);
	      border-top-color: currentColor;
	    }}
	    button.is-busy .spinner {{
	      display: inline-block;
	    }}
	    .button.ghost {{
	      border-color: var(--line);
	    }}
    form {{
      margin: 0;
    }}
    .notice {{
      border: 1px solid var(--line-bright);
      background: #1b211f;
      padding: 14px 16px;
    }}
	    .notice strong {{
	      display: block;
	      margin-bottom: 8px;
	      color: var(--text);
	      font-family: var(--mono);
	      font-size: 0.82rem;
	      letter-spacing: 0;
	      text-transform: uppercase;
	    }}
		    .notice ul {{
		      margin: 0;
		      padding-left: 18px;
		      color: var(--muted);
		    }}
		    .activity {{
		      display: grid;
		      grid-template-columns: auto minmax(0, 1fr);
		      gap: 12px;
		      align-items: center;
		      border: 1px solid rgba(22, 178, 200, 0.36);
		      background: rgba(10, 143, 163, 0.07);
		      padding: 12px;
		    }}
		    .activity[data-mode="stop"] {{
		      border-color: rgba(239, 230, 160, 0.42);
		      background: rgba(239, 230, 160, 0.07);
		    }}
		    .activity[data-stage="error"] {{
		      border-color: rgba(229, 72, 77, 0.52);
		      background: rgba(229, 72, 77, 0.08);
		    }}
		    .activity[hidden] {{
		      display: none;
		    }}
		    .activity-spinner {{
		      width: 18px;
		      height: 18px;
		      border: 2px solid rgba(243, 240, 197, 0.22);
		      border-top-color: var(--accent-bright);
		      border-radius: 50%;
		      animation: spin 780ms linear infinite;
		    }}
		    .activity[data-mode="stop"] .activity-spinner {{
		      border-top-color: var(--warn);
		    }}
		    .activity[data-stage="error"] .activity-spinner {{
		      border-color: var(--danger);
		      animation: none;
		    }}
		    .activity-copy {{
		      display: grid;
		      gap: 4px;
		      min-width: 0;
		    }}
		    .activity-copy p {{
		      color: var(--text);
		      font-size: 0.88rem;
		      overflow-wrap: anywhere;
		    }}
	    .activity-head {{
	      display: flex;
	      align-items: center;
	      justify-content: space-between;
	      gap: 12px;
	    }}
		    .activity-stage {{
		      color: var(--muted);
		      font-family: var(--mono);
		      font-size: 0.7rem;
		      font-weight: 800;
		      letter-spacing: 0;
		      text-transform: uppercase;
		      text-align: right;
		    }}
	    .app-card.is-launching, .dashboard.is-launching .panel {{
	      border-color: rgba(22, 178, 200, 0.72);
	      box-shadow: inset 0 0 0 1px rgba(22, 178, 200, 0.12);
	    }}
		    .detail-layout {{
		      display: grid;
		      grid-template-columns: minmax(0, 1fr) minmax(320px, 0.72fr);
	      gap: 14px;
	    }}
	    .control-stack {{
	      display: grid;
	      gap: 16px;
	    }}
	    .detail-title {{
      margin-top: 10px;
	      color: var(--text);
	      font-family: var(--mono);
	      font-size: 3.6rem;
	      font-weight: 300;
	      letter-spacing: 0;
	      line-height: 1.05;
	      text-transform: uppercase;
	    }}
    .unit-grid {{
      display: grid;
      gap: 8px;
    }}
    .unit-row {{
      display: grid;
      grid-template-columns: minmax(180px, 1fr) minmax(180px, 1.1fr) auto;
      gap: 10px;
      align-items: center;
      border: 1px solid var(--line);
      padding: 10px;
      color: var(--muted);
      font-family: var(--mono);
      font-size: 0.78rem;
    }}
    .unit-name {{
      color: var(--text);
      overflow-wrap: anywhere;
    }}
    .unit-state, .unit-result {{
      overflow-wrap: anywhere;
    }}
    .footer-note {{
	      color: var(--dim);
	      font-family: var(--mono);
	      font-size: 0.68rem;
	      letter-spacing: 0;
	      text-transform: uppercase;
	    }}
	    @keyframes spin {{
	      to {{
	        transform: rotate(360deg);
	      }}
	    }}
	    @media (max-width: 900px) {{
	      .hero, .detail-layout {{
	        grid-template-columns: 1fr;
	      }}
	      .hero h1 {{
	        font-size: 2.8rem;
	      }}
	      .hero-number {{
	        font-size: 5.5rem;
	      }}
	      .detail-title {{
	        font-size: 3rem;
	      }}
	      .hero-metric {{
	        justify-self: start;
	        text-align: left;
      }}
      .summary-grid, .app-grid {{
        grid-template-columns: 1fr;
      }}
      .unit-row {{
        grid-template-columns: 1fr;
      }}
    }}
    @media (max-width: 560px) {{
      main {{
        width: min(100% - 18px, 1180px);
        margin-top: 9px;
      }}
	      .topbar, .panel-header, .panel-body, .hero, .app-card {{
	        padding-left: 12px;
	        padding-right: 12px;
	      }}
	      .hero h1 {{
	        font-size: 2.1rem;
	      }}
	      .hero-number {{
	        font-size: 4.1rem;
	      }}
	      .detail-title {{
	        font-size: 2.2rem;
	      }}
	      .brand {{
	        align-items: flex-start;
	        flex-direction: column;
	        gap: 4px;
	      }}
	      .activity-head {{
	        align-items: flex-start;
	        flex-direction: column;
	      }}
	      .activity-stage {{
	        text-align: left;
	      }}
      .actions {{
        display: grid;
        grid-template-columns: 1fr;
      }}
      .actions > *, .actions button, .actions .button {{
        width: 100%;
      }}
    }}
  </style>
</head>
<body>
	  <main>
	    <nav class="topbar" aria-label="Dashboard">
      <a class="brand" href="/">
        <span class="brand-name">On-demand apps</span>
      </a>
      <span class="topbar-meta">productivity-vm</span>
	    </nav>
	    {body}
	  </main>
	  <script>{INTERACTION_SCRIPT}</script>
	</body>
	</html>
	"""


def render_index(user=""):
    statuses = [(app, app_status(app)) for app in CONFIG["apps"]]
    running = sum(1 for _app, status in statuses if status["status"] == "running")
    stopped = sum(1 for _app, status in statuses if status["status"] == "stopped")
    blocked = statuses[0][1]["blocked"] if statuses else []

    block_html = ""
    if blocked:
        block_html = (
            '<section class="notice"><strong>Control actions paused</strong><ul>'
            + "".join(f"<li>{esc(reason)}</li>" for reason in blocked)
            + "</ul></section>"
        )

    cards = []
    for app, status in statuses:
        active_units = active_unit_count(status)
        total_units = len(status["units"])
        description = app.get("description", "App")
        safety = "Locked" if status["blocked"] else "Clear"
        cards.append(
            f"""<article class="app-card" data-app-card data-app-id="{esc(app["id"])}" data-status="{esc(status["status"])}" data-active-units="{esc(active_unit_count(status))}" data-unit-count="{esc(len(status["units"]))}" data-blocked-count="{esc(len(status["blocked"]))}">
  <div class="row">
    <div>
      <div class="label">{esc(description)}</div>
      <h2 class="app-title">{esc(app["name"])}</h2>
    </div>
    <div class="status-ring" data-role="status-ring" data-value="{esc(status_ring_label(status["status"]))}" aria-hidden="true"></div>
  </div>
  <div class="card-mid">
    <div class="state-summary">
      <span class="status {esc(status["status"])}" data-role="status-chip" tabindex="0">{esc(status_label(status["status"]))}</span>
      <p data-role="state-copy">{esc(state_caption(status["status"]))}</p>
    </div>
    {render_state_flow(status, include_copy=False)}
    <div class="quick-stats">
      <div class="quick-stat"><span>Units</span><strong data-role="unit-count">{esc(active_units)}/{esc(total_units)} units active</strong></div>
      <div class="quick-stat"><span>Health</span><strong data-role="health">{esc(status_label(status["status"]))}</strong></div>
      <div class="quick-stat"><span>Safety</span><strong data-role="safety">{esc(safety)}</strong></div>
    </div>
  </div>
  {render_activity(status)}
  {render_actions(app, status, user, compact=True)}
</article>"""
        )

    body = f"""<section class="dashboard">
  <section class="panel hero">
    <div>
      <div class="eyebrow">Productivity VM</div>
      <h1>On-demand apps</h1>
      <p class="hero-copy" data-summary="hero-copy">{esc(running)} running / {esc(stopped)} stopped / {esc(len(blocked))} safety locks</p>
    </div>
    <div class="hero-metric">
      <div class="hero-number"><span data-summary="running">{esc(running)}</span><small>/<span data-summary="total">{esc(len(statuses))}</span></small></div>
      <div class="hero-caption">apps running</div>
    </div>
  </section>
  {block_html}
  <section class="summary-grid">
    <div class="summary-tile"><div class="label">Running</div><div class="summary-value" data-summary="running">{esc(running)}</div></div>
    <div class="summary-tile"><div class="label">Stopped</div><div class="summary-value" data-summary="stopped">{esc(stopped)}</div></div>
    <div class="summary-tile"><div class="label">Safety</div><div class="summary-value" data-summary="safety">{esc(len(blocked))}</div></div>
  </section>
  <section class="panel">
    <div class="panel-header">
	      <div class="eyebrow">Apps</div>
      <div class="footer-note">systemd + health checks</div>
    </div>
    <div class="panel-body">
      <div class="app-grid">{"".join(cards)}</div>
    </div>
  </section>
</section>"""
    return render_page("On-demand apps", body)


def render_app(app, message=None, status_code=HTTPStatus.OK, user=""):
    status = app_status(app)
    blocked = status["blocked"]
    block_html = ""
    if blocked:
        block_html = (
            '<section class="notice"><strong>Control actions paused</strong><ul>'
            + "".join(f"<li>{esc(reason)}</li>" for reason in blocked)
            + "</ul></section>"
        )
    message_html = f'<section class="notice">{esc(message)}</section>' if message else ""
    body = f"""<section class="dashboard" data-app-card data-app-id="{esc(app["id"])}" data-status="{esc(status["status"])}" data-active-units="{esc(active_unit_count(status))}" data-unit-count="{esc(len(status["units"]))}" data-blocked-count="{esc(len(status["blocked"]))}">
  {message_html}
  {block_html}
  <section class="detail-layout">
    <section class="panel hero">
      <div>
	        <div class="eyebrow">App</div>
        <h1 class="detail-title">{esc(app["name"])}</h1>
        <p class="hero-copy">{esc(app.get("description", ""))}</p>
	      </div>
	      <div class="hero-metric">
	        <span class="status {esc(status["status"])}" data-role="status-chip">{esc(status_label(status["status"]))}</span>
	      </div>
    </section>
    <section class="panel">
      <div class="panel-header">
        <div class="eyebrow">Controls</div>
        <div class="footer-note" data-role="unit-count">{esc(active_unit_count(status))}/{esc(len(status["units"]))} units active</div>
      </div>
	      <div class="panel-body control-stack">
	        {render_state_flow(status)}
	        {render_activity(status)}
	        {render_actions(app, status, user)}
	      </div>
    </section>
  </section>
  <section class="panel">
    <div class="panel-header">
      <div class="eyebrow">Systemd State</div>
      <div class="footer-note">{esc(app["id"])}</div>
    </div>
    <div class="panel-body">
      <div class="unit-grid">{render_unit_grid(status)}</div>
    </div>
  </section>
</section>"""
    return render_page(app["name"], body, status_code)


class Handler(BaseHTTPRequestHandler):
    server_version = "OnDemandAppsDashboard/1"

    def current_user(self):
        return self.headers.get(CONFIG.get("auth_header", "X-authentik-username"), "")

    def log_message(self, fmt, *args):
        user = self.current_user() or "-"
        sys.stderr.write("%s %s - %s\n" % (self.address_string(), user, fmt % args))

    def send_body(self, status, content_type, body, include_body=True):
        body_bytes = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body_bytes)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if include_body:
            self.wfile.write(body_bytes)

    def send_json(self, status, payload):
        self.send_body(
            status,
            "application/json; charset=utf-8",
            json.dumps(payload, sort_keys=True) + "\n",
        )

    def wants_json(self):
        accept = self.headers.get("Accept", "")
        requested_with = self.headers.get("X-Requested-With", "")
        return "application/json" in accept or requested_with == "fetch"

    def redirect(self, location):
        self.send_response(HTTPStatus.SEE_OTHER)
        self.send_header("Location", location)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def require_auth(self, parsed):
        if parsed.path == "/healthz" or (
            parsed.path.startswith("/apps/") and parsed.path.endswith("/status")
        ):
            return True
        if not CONFIG.get("require_auth_header", True):
            return True
        header = CONFIG.get("auth_header", "X-authentik-username")
        if self.headers.get(header):
            return True
        status, content_type, body = render_page(
            "Unauthorized",
            "<section class=\"card\">This control surface must be opened through Authentik.</section>",
            HTTPStatus.UNAUTHORIZED,
        )
        self.send_body(status, content_type, body)
        return False

    def handle_GET(self, include_body=True):
        parsed = urlparse(self.path)
        if not self.require_auth(parsed):
            return
        if parsed.path == "/healthz":
            self.send_body(HTTPStatus.OK, "text/plain; charset=utf-8", "ok\n", include_body)
            return
        if parsed.path == "/":
            self.send_body(*render_index(user=self.current_user()), include_body=include_body)
            return
        parts = [part for part in parsed.path.split("/") if part]
        if len(parts) == 2 and parts[0] == "apps" and parts[1] in APPS:
            self.send_body(*render_app(APPS[parts[1]], user=self.current_user()), include_body=include_body)
            return
        if len(parts) == 3 and parts[0] == "apps" and parts[1] in APPS and parts[2] == "status":
            self.send_body(
                HTTPStatus.OK,
                "application/json; charset=utf-8",
                json.dumps(app_status(APPS[parts[1]]), sort_keys=True) + "\n",
                include_body,
            )
            return
        self.send_error(HTTPStatus.NOT_FOUND)

    def do_GET(self):
        self.handle_GET(include_body=True)

    def do_HEAD(self):
        self.handle_GET(include_body=False)

    def do_POST(self):
        parsed = urlparse(self.path)
        if not self.require_auth(parsed):
            return
        parts = [part for part in parsed.path.split("/") if part]
        if len(parts) != 3 or parts[0] != "apps" or parts[1] not in APPS:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        app = APPS[parts[1]]
        action = parts[2]
        wants_json = self.wants_json()
        length = int(self.headers.get("Content-Length", "0") or "0")
        form = {}
        if length:
            form = parse_qs(self.rfile.read(length).decode("utf-8"))
        if action in {"start", "stop"} and not csrf_valid(
            self.current_user(),
            app["id"],
            action,
            (form.get("csrf") or [""])[0],
        ):
            if wants_json:
                self.send_json(
                    HTTPStatus.FORBIDDEN,
                    {
                        "error": "Action refused because the form token was invalid.",
                        "ok": False,
                        "status": app_status(app),
                    },
                )
                return
            self.send_body(
                *render_app(
                    app,
                    "Action refused because the form token was invalid.",
                    HTTPStatus.FORBIDDEN,
                    user=self.current_user(),
                )
            )
            return
        with ACTION_LOCK:
            blocked = blocking_reasons()
            if blocked:
                if wants_json:
                    self.send_json(
                        HTTPStatus.LOCKED,
                        {
                            "error": "Action refused because maintenance is active.",
                            "ok": False,
                            "status": app_status(app),
                        },
                    )
                    return
                self.send_body(
                    *render_app(
                        app,
                        "Action refused because maintenance is active.",
                        HTTPStatus.LOCKED,
                        user=self.current_user(),
                    )
                )
                return
            try:
                if action == "start":
                    for unit in app.get("start_units", []):
                        systemctl("start", unit, check=True)
                    if wants_json:
                        self.send_json(
                            HTTPStatus.ACCEPTED,
                            {
                                "ok": True,
                                "phase": "starting",
                                "status": app_status(app),
                                "url": app["url"],
                            },
                        )
                        return
                    if wait_for_health(app):
                        self.redirect(app["url"])
                        return
                    self.send_body(
                        *render_app(
                            app,
                            "Start command completed, but the health check is still pending.",
                            HTTPStatus.ACCEPTED,
                            user=self.current_user(),
                        )
                    )
                    return
                if action == "stop":
                    for unit in app.get("stop_units", []):
                        systemctl("stop", unit, check=True)
                    reset_failed_units(app.get("stop_units", []) + app.get("status_units", []))
                    if wants_json:
                        self.send_json(
                            HTTPStatus.OK,
                            {
                                "ok": True,
                                "phase": "stopping",
                                "status": app_status(app),
                                "url": app["url"],
                            },
                        )
                        return
                    self.redirect(f"/apps/{app['id']}")
                    return
            except RuntimeError as exc:
                if wants_json:
                    self.send_json(
                        HTTPStatus.INTERNAL_SERVER_ERROR,
                        {
                            "error": str(exc),
                            "ok": False,
                            "status": app_status(app),
                        },
                    )
                    return
                self.send_body(
                    *render_app(
                        app,
                        str(exc),
                        HTTPStatus.INTERNAL_SERVER_ERROR,
                        user=self.current_user(),
                    )
                )
                return
        self.send_error(HTTPStatus.NOT_FOUND)


def main():
    listen = CONFIG.get("listen", {})
    address = listen.get("address", "0.0.0.0")
    port = int(listen.get("port", 8092))
    server = ThreadingHTTPServer((address, port), Handler)
    print(f"listening on {address}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
