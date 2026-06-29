(function () {
  const POLL_INTERVAL_MS = 3000;
  const DEFAULT_TASK_ID = "task-local";

  let activeTab = localStorage.getItem("aiSdlcDashboardTab") || "overview";
  let activeMemoryProvider = localStorage.getItem("aiSdlcMemoryProvider") || "adr";
  let activeMemorySource = localStorage.getItem("aiSdlcMemorySource") || "";
  let activeTaskId = localStorage.getItem("aiSdlcActiveTaskId") || "";
  let pendingRender = false;
  let polling = false;

  const byId = (id) => document.getElementById(id);
  const text = (value, fallback = "-") => {
    if (value === undefined || value === null || value === "") return fallback;
    return String(value);
  };
  const safeClass = (value) => text(value, "unknown").toLowerCase().replace(/[^a-z0-9_-]+/g, "_");
  const escapeHtml = (value) => text(value, "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

  const badge = (value) => `<span class="badge status-${safeClass(value)}">${escapeHtml(value || "unknown")}</span>`;
  const metric = (label, value) => `<div class="metric"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`;

  const getData = () => {
    const state = window.AI_SDLC_STATE || {};
    return {
      state,
      events: window.AI_SDLC_EVENTS || [],
      safety: window.AI_SDLC_SAFETY || null,
      doctor: window.AI_SDLC_DOCTOR || null,
      lane: window.AI_SDLC_LANE || null,
      compliance: window.AI_SDLC_COMPLIANCE || null,
      contextMemory: window.AI_SDLC_CONTEXT_MEMORY || null,
      memoryContent: window.AI_SDLC_MEMORY_CONTENT || null,
      integrations: window.AI_SDLC_INTEGRATIONS || null,
      tokenUsage: window.AI_SDLC_TOKEN_USAGE || null,
      config: window.AI_SDLC_CONFIG || null,
      summary: window.AI_SDLC_SUMMARY || null,
      profile: state.project || window.AI_SDLC_PROFILE || {}
    };
  };

  const hasActiveSelection = () => {
    const selection = window.getSelection ? window.getSelection() : null;
    return !!(selection && selection.toString());
  };

  const compactTime = (value) => {
    if (!value) return "-";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return value;
    return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  };

  const setActiveTab = (name) => {
    activeTab = name;
    localStorage.setItem("aiSdlcDashboardTab", name);
    document.querySelectorAll("[data-app-tab]").forEach((button) => {
      button.classList.toggle("active", button.dataset.appTab === name);
    });
    document.querySelectorAll("[data-tab-panel]").forEach((panel) => {
      panel.classList.toggle("active", panel.dataset.tabPanel === name);
    });
  };

  const eventTaskId = (event) => event.taskId || DEFAULT_TASK_ID;
  const taskEvents = (events, taskId) => events.filter((event) => eventTaskId(event) === taskId);

  const getTasks = (state, events) => {
    if (Array.isArray(state.tasks)) return state.tasks;

    const fallbackEvents = events.length ? events : [{ taskId: DEFAULT_TASK_ID, message: "Local task", status: "pending", role: state.activeRole || "system" }];
    const groups = new Map();
    fallbackEvents.forEach((event) => {
      const id = eventTaskId(event);
      if (!groups.has(id)) groups.set(id, []);
      groups.get(id).push(event);
    });

    return Array.from(groups.entries()).map(([taskId, items], index) => {
      const latest = items[items.length - 1] || {};
      const titleEvent = items.slice().reverse().find((event) => event.taskTitle);
      const artifacts = Array.from(new Set(items.flatMap((event) => event.artifacts || []).filter(Boolean)));
      return {
        batchId: latest.batchId || state.batchId || state.runId || "local",
        taskId,
        title: (titleEvent && titleEvent.taskTitle) || latest.message || taskId,
        order: latest.taskOrder || index + 1,
        status: latest.taskStatus || latest.status || "running",
        activeRole: latest.role || state.activeRole || "system",
        decision: latest.status || "review",
        eventCount: items.length,
        artifactCount: artifacts.length,
        reopenCount: items.filter((event) => event.eventType === "reopen" || event.status === "reopened" || event.status === "revision_requested").length,
        reopenHistory: items
          .filter((event) => event.eventType === "reopen" || event.status === "reopened" || event.status === "revision_requested")
          .map((event) => ({
            timeUtc: event.timeUtc || "",
            fromRole: (event.reopen && event.reopen.fromRole) || event.role || "",
            toRole: (event.reopen && event.reopen.toRole) || "",
            severity: (event.reopen && event.reopen.severity) || "warning",
            reason: (event.reopen && event.reopen.reason) || event.message || "",
            message: event.message || ""
          })),
        startedAtUtc: (items[0] || {}).timeUtc || "",
        updatedAtUtc: latest.timeUtc || "",
        latestMessage: latest.message || "",
        artifacts,
        roles: state.roles || []
      };
    });
  };

  const selectTask = (state, tasks) => {
    if (!tasks.length) return null;
    const persisted = tasks.find((task) => task.taskId === activeTaskId);
    const fromState = tasks.find((task) => task.taskId === state.activeTaskId);
    const running = tasks.find((task) => task.status === "running");
    const waiting = tasks.find((task) => task.status === "waiting");
    const selected = persisted || fromState || running || waiting || tasks[tasks.length - 1];
    activeTaskId = selected.taskId;
    localStorage.setItem("aiSdlcActiveTaskId", activeTaskId);
    return selected;
  };

  const gateCard = (title, decision, details) => `
    <article class="gate-card">
      <div class="panel-header compact">
        <h4>${escapeHtml(title)}</h4>
        ${badge(decision || "missing")}
      </div>
      ${details.join("")}
    </article>
  `;

  const renderTaskSummary = (state, tasks) => {
    const summary = state.taskSummary || {};
    byId("taskTotal").textContent = text(summary.total ?? tasks.length, "0");
    byId("taskRunning").textContent = text(summary.running ?? tasks.filter((task) => task.status === "running").length, "0");
    byId("taskCompleted").textContent = text(summary.completed ?? tasks.filter((task) => task.status === "completed").length, "0");
    byId("taskBlocked").textContent = text((summary.blocked || 0) + (summary.failed || 0), "0");
  };

  const renderGateGrid = ({ doctor, lane, compliance, safety, tokenUsage, contextMemory, integrations }) => {
    const cards = [
      gateCard("Doctor", doctor && doctor.decision, doctor ? [
        metric("Passed", doctor.passed),
        metric("Blockers", Array.isArray(doctor.blockers) ? doctor.blockers.length : 0),
        metric("Warnings", Array.isArray(doctor.warnings) ? doctor.warnings.length : 0)
      ] : [`<p class="muted">Run doctor to verify framework readiness.</p>`]),
      gateCard("Execution Lane", lane && (lane.decision || "selected"), lane ? [
        metric("Lane", `${lane.lane || "-"} (${lane.title || "-"})`),
        metric("Risk", lane.riskScore ?? "-"),
        metric("Validation", lane.requireValidationExecution ? "required" : "advisory")
      ] : [`<p class="muted">No lane report yet.</p>`]),
      gateCard("Compliance", compliance && compliance.decision, compliance ? [
        metric("Passed", compliance.passed),
        metric("Blockers", Array.isArray(compliance.blockers) ? compliance.blockers.length : 0),
        metric("Warnings", Array.isArray(compliance.warnings) ? compliance.warnings.length : 0)
      ] : [`<p class="muted">No compliance report yet.</p>`]),
      gateCard("Safety", safety && safety.decision, safety ? [
        metric("Passed", safety.passed),
        metric("Blockers", Array.isArray(safety.blockers) ? safety.blockers.length : 0),
        metric("Warnings", Array.isArray(safety.warnings) ? safety.warnings.length : 0)
      ] : [`<p class="muted">Safe-change gate has not run yet.</p>`]),
      gateCard("Token Budget", tokenUsage && tokenUsage.decision, tokenUsage ? [
        metric("Estimate", tokenUsage.estimatedTokens || 0),
        metric("Items", Array.isArray(tokenUsage.countedItems) ? tokenUsage.countedItems.length : 0)
      ] : [`<p class="muted">No token estimate yet.</p>`]),
      gateCard("Context", contextMemory && contextMemory.decision, contextMemory ? [
        metric("Providers", contextMemory.enabledProviders || 0),
        metric("Sources", contextMemory.availableSources || 0)
      ] : [`<p class="muted">No context memory report yet.</p>`]),
      gateCard("Integrations", integrations && integrations.decision, integrations ? [
        metric("Enabled", integrations.enabledIntegrations || 0),
        metric("Ready", integrations.readyIntegrations || 0)
      ] : [`<p class="muted">No integration report yet.</p>`])
    ];

    byId("gateGrid").innerHTML = cards.join("");
  };

  const roleGraphHtml = (roles, activeRole) => (roles || []).map((role, index) => {
    const active = role.id === activeRole ? " active" : "";
    return `
      <article class="role-node${active}">
        <span class="role-index">${index + 1}</span>
        <span class="role-title">${escapeHtml(role.title || role.id)}</span>
        ${badge(role.status || "pending")}
        <p class="role-message">${escapeHtml(role.message || role.purpose || "Waiting for role activity.")}</p>
      </article>
    `;
  }).join("") || `<p class="muted">No role flow loaded.</p>`;

  const renderRoleGraph = (task) => {
    const roles = task && Array.isArray(task.roles) ? task.roles : [];
    byId("roleCount").textContent = `${roles.length} roles`;
    byId("roleGraphTitle").textContent = task ? `Execution graph / ${task.title}` : "Execution graph";
    byId("roleGraph").innerHTML = roleGraphHtml(roles, task && task.activeRole);
  };

  const renderActivity = (events, selectedTask) => {
    const scoped = selectedTask ? taskEvents(events, selectedTask.taskId) : events;
    byId("eventCount").textContent = `${scoped.length} events`;
    const recent = scoped.slice(-6).reverse();
    byId("liveFeed").innerHTML = recent.map((event) => `
      <article class="feed-item">
        <div class="panel-header compact">
          <strong>${escapeHtml(event.role)}</strong>
          ${badge(event.status)}
        </div>
        <p>${escapeHtml(event.message)}</p>
        <span class="muted-label">${escapeHtml(compactTime(event.timeUtc))}</span>
      </article>
    `).join("") || `<p class="muted">No events for the selected task yet.</p>`;
  };

  const collectArtifacts = (state, summary, selectedTask) => {
    const artifacts = new Map();
    ((selectedTask && selectedTask.roles) || state.roles || []).forEach((role) => {
      (role.artifacts || []).forEach((artifact) => {
        if (artifact) artifacts.set(String(artifact), { path: String(artifact), source: role.title || role.id });
      });
    });
    ((selectedTask && selectedTask.artifacts) || []).forEach((artifact) => {
      if (artifact) artifacts.set(String(artifact), { path: String(artifact), source: selectedTask.title || selectedTask.taskId });
    });
    if (summary && summary.reports) {
      Object.keys(summary.reports).forEach((key) => {
        const path = summary.reports[key];
        if (path) artifacts.set(String(path), { path: String(path), source: key });
      });
    }
    return Array.from(artifacts.values());
  };

  const normalizeFinding = (group, item) => {
    if (item && typeof item === "object") {
      return {
        group,
        code: item.code || "finding",
        message: item.message || item.detail || item.reason || JSON.stringify(item),
        path: item.path || item.file || ""
      };
    }

    return {
      group,
      code: "finding",
      message: text(item, "No detail provided."),
      path: ""
    };
  };

  const renderEvidence = ({ state, summary, compliance, safety, doctor }, selectedTask) => {
    const artifacts = collectArtifacts(state, summary, selectedTask);
    byId("artifactCount").textContent = `${artifacts.length} artifacts`;
    byId("artifactList").innerHTML = artifacts.map((artifact) => `
      <article class="artifact-item">
        <strong>${escapeHtml(artifact.source)}</strong>
        <p><code>${escapeHtml(artifact.path)}</code></p>
      </article>
    `).join("") || `<p class="muted">No artifacts have been reported for the selected task yet.</p>`;

    const findings = [
      ...((compliance && Array.isArray(compliance.blockers)) ? compliance.blockers.map((item) => normalizeFinding("Compliance blocker", item)) : []),
      ...((compliance && Array.isArray(compliance.warnings)) ? compliance.warnings.map((item) => normalizeFinding("Compliance warning", item)) : []),
      ...((safety && Array.isArray(safety.blockers)) ? safety.blockers.map((item) => normalizeFinding("Safety blocker", item)) : []),
      ...((safety && Array.isArray(safety.warnings)) ? safety.warnings.map((item) => normalizeFinding("Safety warning", item)) : []),
      ...((doctor && Array.isArray(doctor.warnings)) ? doctor.warnings.map((item) => normalizeFinding("Doctor warning", item)) : [])
    ];
    byId("findingsStatus").textContent = `${findings.length} findings`;
    byId("findingsPanel").innerHTML = findings.map((item) => `
      <article class="finding-item">
        <div class="panel-header compact">
          <strong>${escapeHtml(item.group)}</strong>
          ${badge(item.code || "finding")}
        </div>
        <p>${escapeHtml(item.message || item.code || item)}</p>
        ${item.path ? `<p><code>${escapeHtml(item.path)}</code></p>` : ""}
      </article>
    `).join("") || `<p class="muted">No blockers or warnings reported.</p>`;
  };

  const renderTasks = (tasks, events, selectedTask) => {
    byId("taskQueueStatus").textContent = `${tasks.length} tasks`;
    byId("taskQueue").innerHTML = tasks.map((task) => {
      const active = selectedTask && task.taskId === selectedTask.taskId ? " active" : "";
      return `
        <button class="task-row${active}" type="button" data-task-id="${escapeHtml(task.taskId)}" aria-expanded="${active ? "true" : "false"}">
          <span class="task-row-top">
            <strong>${escapeHtml(task.order || "-")}. ${escapeHtml(task.title || task.taskId)}</strong>
            ${badge(task.status || "unknown")}
          </span>
          <span class="task-row-meta">
            ${escapeHtml(task.activeRole || "-")} / ${escapeHtml(task.eventCount || 0)} events / ${escapeHtml(task.artifactCount || 0)} artifacts${task.reopenCount ? ` / ${escapeHtml(task.reopenCount)} reopens` : ""}
          </span>
          <span class="task-row-message">${escapeHtml(task.latestMessage || "Waiting for task activity.")}</span>
        </button>
      `;
    }).join("") || `<p class="muted">No tasks have been recorded yet.</p>`;

    if (!selectedTask) {
      byId("selectedTaskTitle").textContent = "No task selected";
      byId("selectedTaskStatus").textContent = "unknown";
      byId("selectedTaskStatus").className = "badge status-unknown";
      byId("selectedTaskMeta").innerHTML = "";
      byId("selectedTaskRoleGraph").innerHTML = `<p class="muted">No task selected.</p>`;
      byId("selectedTaskEvents").innerHTML = `<p class="muted">No task selected.</p>`;
      byId("selectedTaskArtifacts").innerHTML = `<p class="muted">No task selected.</p>`;
      byId("selectedTaskReopenCount").textContent = "0 reopens";
      byId("selectedTaskReopens").innerHTML = `<p class="muted">No task selected.</p>`;
      return;
    }

    const scoped = taskEvents(events, selectedTask.taskId);
    byId("selectedTaskTitle").textContent = selectedTask.title || selectedTask.taskId;
    byId("selectedTaskStatus").textContent = selectedTask.status || "unknown";
    byId("selectedTaskStatus").className = `badge status-${safeClass(selectedTask.status)}`;
    byId("selectedTaskMeta").innerHTML = [
      metric("Task ID", selectedTask.taskId),
      metric("Batch", selectedTask.batchId || "-"),
      metric("Active role", selectedTask.activeRole || "-"),
      metric("Reopens", selectedTask.reopenCount || 0),
      metric("Updated", compactTime(selectedTask.updatedAtUtc))
    ].join("");
    byId("selectedTaskRoleCount").textContent = `${(selectedTask.roles || []).length} roles`;
    byId("selectedTaskRoleGraph").innerHTML = roleGraphHtml(selectedTask.roles || [], selectedTask.activeRole);
    byId("selectedTaskEventCount").textContent = `${scoped.length} events`;
    byId("selectedTaskEvents").innerHTML = scoped.slice().reverse().map((event) => `
      <article class="timeline-item">
        <span class="muted-label">${escapeHtml(compactTime(event.timeUtc))}</span>
        <span>${escapeHtml(event.role)} ${badge(event.status)}</span>
        <div>
          <p>${escapeHtml(event.message)}</p>
          ${event.eventType === "reopen" && event.reopen ? `<p class="reopen-inline">${escapeHtml(event.reopen.fromRole || event.role)} -> ${escapeHtml(event.reopen.toRole || "-")}: ${escapeHtml(event.reopen.reason || "")}</p>` : ""}
        </div>
      </article>
    `).join("") || `<p class="muted">No events for this task.</p>`;
    byId("selectedTaskArtifactCount").textContent = `${(selectedTask.artifacts || []).length} artifacts`;
    byId("selectedTaskArtifacts").innerHTML = (selectedTask.artifacts || []).map((artifact) => `
      <article class="artifact-item"><p><code>${escapeHtml(artifact)}</code></p></article>
    `).join("") || `<p class="muted">No artifacts for this task.</p>`;
    const reopens = Array.isArray(selectedTask.reopenHistory) ? selectedTask.reopenHistory : [];
    byId("selectedTaskReopenCount").textContent = `${reopens.length} reopens`;
    byId("selectedTaskReopens").innerHTML = reopens.slice().reverse().map((item) => `
      <article class="reopen-item severity-${safeClass(item.severity)}">
        <div class="panel-header compact">
          <strong>${escapeHtml(item.fromRole || "-")} -> ${escapeHtml(item.toRole || "-")}</strong>
          ${badge(item.severity || "warning")}
        </div>
        <p>${escapeHtml(item.reason || item.message || "No reason recorded.")}</p>
        <span class="muted-label">${escapeHtml(compactTime(item.timeUtc))}</span>
      </article>
    `).join("") || `<p class="muted">No reopen loops for this task.</p>`;
  };

  const getMemoryProvider = (contextMemory, memoryContent, name) => {
    const reportProviders = contextMemory && Array.isArray(contextMemory.providers) ? contextMemory.providers : [];
    const contentProviders = memoryContent && Array.isArray(memoryContent.providers) ? memoryContent.providers : [];
    const report = reportProviders.find((provider) => provider.name === name) || null;
    const content = contentProviders.find((provider) => provider.name === name) || null;
    return { report, content };
  };

  const renderMemory = (contextMemory, memoryContent) => {
    const providers = contextMemory && Array.isArray(contextMemory.providers) ? contextMemory.providers : [];
    if (providers.length && !providers.some((provider) => provider.name === activeMemoryProvider)) {
      activeMemoryProvider = providers[0].name;
    }

    const memorySummary = contextMemory
      ? `${contextMemory.enabledProviders || 0} enabled / ${contextMemory.availableSources || 0} available`
      : "No context report";
    byId("memoryStatus").textContent = memorySummary;

    byId("memoryProviderList").innerHTML = providers.map((provider) => `
      <button class="provider-item${provider.name === activeMemoryProvider ? " active" : ""}" type="button" data-memory-provider="${escapeHtml(provider.name)}">
        <span>${escapeHtml(provider.name)}</span>
        ${badge(provider.enabled ? provider.mode || "enabled" : "disabled")}
      </button>
    `).join("") || `<p class="muted">No memory providers configured.</p>`;

    const { report, content } = getMemoryProvider(contextMemory, memoryContent, activeMemoryProvider);
    const reportSources = report && Array.isArray(report.sources) ? report.sources : [];
    const contentSources = content && Array.isArray(content.sources) ? content.sources : [];
    const sources = reportSources.map((source) => {
      const preview = contentSources.find((item) => item.path === source.path || item.resolvedPath === source.resolvedPath) || null;
      return { ...source, preview };
    });

    if (sources.length && !sources.some((source) => (source.path || source.resolvedPath) === activeMemorySource)) {
      activeMemorySource = sources[0].path || sources[0].resolvedPath || "";
    }

    byId("memorySourceStatus").textContent = report ? `${report.availableSources || 0}/${report.configuredSources || sources.length} available` : "No provider selected";
    byId("memorySourceList").innerHTML = sources.map((source) => {
      const key = source.path || source.resolvedPath || "";
      return `
        <button class="source-item${key === activeMemorySource ? " active" : ""}" type="button" data-memory-source="${escapeHtml(key)}">
          <code>${escapeHtml(source.path || source.resolvedPath || "-")}</code>
          ${badge(source.status || "unknown")}
        </button>
      `;
    }).join("") || `<p class="muted">This provider has no configured sources.</p>`;

    const selected = sources.find((source) => (source.path || source.resolvedPath) === activeMemorySource) || null;
    byId("memoryPreviewTitle").textContent = selected ? (selected.path || selected.resolvedPath || "Memory Preview") : "Memory Preview";
    if (!selected) {
      byId("memoryPreviewStatus").textContent = "Select a source";
      byId("memoryPreview").textContent = "No memory source selected.";
      return;
    }

    const preview = selected.preview;
    const previewSummary = preview
      ? `${preview.sizeBytes || 0} bytes${preview.truncated ? " / truncated" : ""}`
      : selected.status || "unavailable";
    byId("memoryPreviewStatus").textContent = previewSummary;
    byId("memoryPreview").textContent = preview && preview.content
      ? preview.content
      : `No preview available for this source.\n\nStatus: ${selected.status || "unknown"}\nPath: ${selected.resolvedPath || selected.path || "-"}`;
  };

  const renderTimeline = (events, tasks, selectedTask) => {
    byId("timelineStatus").textContent = `${events.length} events / ${tasks.length} tasks`;
    const systemEvents = events.filter((event) => event.taskVisible === false);
    const timelineGroups = tasks.slice();
    if (systemEvents.length) {
      timelineGroups.push({
        taskId: "system",
        title: "System events",
        status: "system",
        eventCount: systemEvents.length,
        artifactCount: systemEvents.flatMap((event) => event.artifacts || []).filter(Boolean).length
      });
    }

    byId("eventsTimeline").innerHTML = timelineGroups.slice().reverse().map((task) => {
      const scoped = taskEvents(events, task.taskId).slice().reverse();
      const open = selectedTask && selectedTask.taskId === task.taskId ? " open" : "";
      return `
        <details class="event-group"${open}>
          <summary>
            <span>
              <strong>${escapeHtml(task.title || task.taskId)}</strong>
              <small>${escapeHtml(task.eventCount || 0)} events / ${escapeHtml(task.artifactCount || 0)} artifacts</small>
            </span>
            ${badge(task.status || "unknown")}
          </summary>
          <div class="timeline">
            ${scoped.map((event) => `
              <article class="timeline-item">
                <span class="muted-label">${escapeHtml(compactTime(event.timeUtc))}</span>
                <span>${escapeHtml(event.role)} ${badge(event.status)}</span>
                <div>
                  <p>${escapeHtml(event.message)}</p>
                  ${event.eventType === "reopen" && event.reopen ? `<p class="reopen-inline">${escapeHtml(event.reopen.fromRole || event.role)} -> ${escapeHtml(event.reopen.toRole || "-")}: ${escapeHtml(event.reopen.reason || "")}</p>` : ""}
                  ${(event.artifacts || []).length ? `<p><code>${escapeHtml((event.artifacts || []).join(", "))}</code></p>` : ""}
                </div>
              </article>
            `).join("") || `<p class="muted">No events for this task.</p>`}
          </div>
        </details>
      `;
    }).join("") || `<p class="muted">No events yet.</p>`;
  };

  const renderConfigModal = () => {
    const { state, profile, doctor, lane, compliance, contextMemory, integrations, tokenUsage, config } = getData();
    if (!config || !Array.isArray(config.files)) {
      byId("configModalBody").innerHTML = `<p class="muted">No dashboard configuration snapshot is available yet.</p>`;
      return;
    }

    const configSummary = {
      run: { id: state.runId, batchId: state.batchId, activeTaskId: state.activeTaskId, activeRole: state.activeRole, decision: state.decision },
      tasks: state.taskSummary || "not generated",
      project: {
        name: profile.projectName || profile.name || "Unknown",
        profile: profile.profileName || "-",
        stack: profile.primaryStack || "-",
        protectedSurfaces: profile.protectedSurfaces || []
      },
      doctor: doctor || "not generated",
      lane: lane || "not generated",
      compliance: compliance || "not generated",
      contextMemory: contextMemory ? {
        decision: contextMemory.decision,
        enabledProviders: contextMemory.enabledProviders,
        availableSources: contextMemory.availableSources
      } : "not generated",
      integrations: integrations ? {
        decision: integrations.decision,
        enabledIntegrations: integrations.enabledIntegrations,
        readyIntegrations: integrations.readyIntegrations
      } : "not generated",
      tokenBudget: tokenUsage ? {
        decision: tokenUsage.decision,
        estimatedTokens: tokenUsage.estimatedTokens,
        thresholds: tokenUsage.thresholds
      } : "not generated"
    };

    byId("configModalBody").innerHTML = `
      <article class="config-file">
        <div class="config-file-header">
          <strong>Active Configuration Summary</strong>
          ${badge(state.decision || "review")}
        </div>
        <pre>${escapeHtml(JSON.stringify(configSummary, null, 2))}</pre>
      </article>
      ${config.files.map((file) => `
        <article class="config-file">
          <div class="config-file-header">
            <strong>${escapeHtml(file.name || file.relativePath)}</strong>
            ${badge(file.present ? "loaded" : "missing")}
          </div>
          <pre>${escapeHtml(`${file.relativePath}\n${file.path}\nsizeBytes: ${file.sizeBytes || 0}`)}</pre>
        </article>
      `).join("")}
    `;
  };

  const renderDashboard = () => {
    if (hasActiveSelection()) {
      pendingRender = true;
      return;
    }

    pendingRender = false;
    const data = getData();
    const { state, events, profile, doctor, lane, compliance, summary } = data;
    const tasks = getTasks(state, events);
    const selectedTask = selectTask(state, tasks);

    byId("runId").textContent = text(state.runId);
    byId("activeRole").textContent = text((selectedTask && selectedTask.activeRole) || state.activeRole);
    byId("activeTask").textContent = text(selectedTask && selectedTask.title);
    byId("projectName").textContent = text(profile.projectName || profile.name || state.projectName || "Unknown Project");
    byId("updatedAt").textContent = text(compactTime(state.updatedAtUtc));
    byId("doctorDecision").textContent = text(doctor && doctor.decision, "unknown");
    byId("laneName").textContent = text((lane && lane.lane) || (summary && summary.lane));
    byId("complianceDecision").textContent = text((compliance && compliance.decision) || (summary && summary.complianceDecision), "review");
    byId("decisionBadge").textContent = text(state.decision, "review");
    byId("decisionBadge").className = `badge status-${safeClass(state.decision || "review")}`;

    const loadedReports = [data.doctor, data.lane, data.compliance, data.safety, data.tokenUsage, data.contextMemory, data.integrations].filter(Boolean).length;
    byId("frameworkStatus").textContent = `${loadedReports}/7 reports`;

    renderTaskSummary(state, tasks);
    renderRoleGraph(selectedTask);
    renderGateGrid(data);
    renderActivity(events, selectedTask);
    renderTasks(tasks, events, selectedTask);
    renderEvidence(data, selectedTask);
    renderMemory(data.contextMemory, data.memoryContent);
    renderTimeline(events, tasks, selectedTask);
    setActiveTab(activeTab);
  };

  const pollRuntimeState = () => {
    if (polling) return;
    polling = true;
    const script = document.createElement("script");
    script.src = `runtime-state.js?ts=${Date.now()}`;
    script.async = true;
    script.onload = () => {
      polling = false;
      script.remove();
      renderDashboard();
    };
    script.onerror = () => {
      polling = false;
      script.remove();
    };
    document.head.appendChild(script);
  };

  const setupInteractions = () => {
    document.querySelectorAll("[data-app-tab]").forEach((button) => {
      button.addEventListener("click", () => setActiveTab(button.dataset.appTab));
    });
    byId("configButton").addEventListener("click", () => {
      renderConfigModal();
      byId("configModal").hidden = false;
    });
    byId("configCloseButton").addEventListener("click", () => {
      byId("configModal").hidden = true;
    });
    byId("configModal").addEventListener("click", (event) => {
      if (event.target && event.target.hasAttribute("data-close-modal")) {
        byId("configModal").hidden = true;
      }
    });
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") byId("configModal").hidden = true;
    });
    document.addEventListener("selectionchange", () => {
      if (pendingRender && !hasActiveSelection()) renderDashboard();
    });
    document.addEventListener("click", (event) => {
      const task = event.target.closest("[data-task-id]");
      if (task) {
        activeTaskId = task.dataset.taskId;
        localStorage.setItem("aiSdlcActiveTaskId", activeTaskId);
        renderDashboard();
      }

      const provider = event.target.closest("[data-memory-provider]");
      if (provider) {
        activeMemoryProvider = provider.dataset.memoryProvider;
        activeMemorySource = "";
        localStorage.setItem("aiSdlcMemoryProvider", activeMemoryProvider);
        localStorage.removeItem("aiSdlcMemorySource");
        renderMemory(getData().contextMemory, getData().memoryContent);
      }

      const source = event.target.closest("[data-memory-source]");
      if (source) {
        activeMemorySource = source.dataset.memorySource;
        localStorage.setItem("aiSdlcMemorySource", activeMemorySource);
        renderMemory(getData().contextMemory, getData().memoryContent);
      }
    });
  };

  setupInteractions();
  renderDashboard();
  window.setInterval(pollRuntimeState, POLL_INTERVAL_MS);
})();
