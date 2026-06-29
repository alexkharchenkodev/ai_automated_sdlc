(function () {
  const state = window.AI_SDLC_STATE || {};
  const events = window.AI_SDLC_EVENTS || [];
  const safety = window.AI_SDLC_SAFETY || null;
  const contextMemory = window.AI_SDLC_CONTEXT_MEMORY || null;
  const integrations = window.AI_SDLC_INTEGRATIONS || null;
  const tokenUsage = window.AI_SDLC_TOKEN_USAGE || null;
  const config = window.AI_SDLC_CONFIG || null;
  const summary = window.AI_SDLC_SUMMARY || null;
  const profile = state.project || window.AI_SDLC_PROFILE || {};

  const byId = (id) => document.getElementById(id);
  const text = (value, fallback = "-") => {
    if (value === undefined || value === null || value === "") return fallback;
    return String(value);
  };

  const escapeHtml = (value) => text(value, "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

  const badge = (value) => `<span class="badge small status-${escapeHtml(value)}">${escapeHtml(value)}</span>`;
  const metric = (label, value) => `<div class="metric"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`;
  const unavailableMessage = (name) => `
    <p class="muted">${escapeHtml(name)} information is unavailable because this provider is disabled or not generated. Edit <code>tools/ai-sdlc/config/context_memory.yaml</code> to enable it for this project.</p>
  `;

  const renderConfigModal = () => {
    if (!config || !Array.isArray(config.files)) {
      byId("configModalBody").innerHTML = `<p class="muted">No dashboard configuration snapshot is available yet.</p>`;
      return;
    }

    const configSummary = {
      project: {
        name: profile.projectName || profile.name || "Unknown",
        profile: profile.profileName || "-",
        stack: profile.primaryStack || "-",
        protectedSurfaces: profile.protectedSurfaces || []
      },
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

  const openConfigModal = () => {
    renderConfigModal();
    byId("configModal").hidden = false;
  };

  const closeConfigModal = () => {
    byId("configModal").hidden = true;
  };

  const getProvider = (name) => {
    const providers = contextMemory && Array.isArray(contextMemory.providers) ? contextMemory.providers : [];
    return providers.find((provider) => provider.name === name) || null;
  };

  const renderMemoryTab = (name) => {
    localStorage.setItem("aiSdlcMemoryTab", name);
    document.querySelectorAll("[data-memory-tab]").forEach((button) => {
      button.classList.toggle("active", button.dataset.memoryTab === name);
    });

    const labels = {
      adr: "ADR",
      rag: "RAG",
      graph_rag: "GraphRAG",
      code_search: "Code Search"
    };
    const provider = getProvider(name);
    if (!contextMemory || !provider || !provider.enabled) {
      byId("memoryPanel").innerHTML = unavailableMessage(labels[name] || name);
      return;
    }

    const sources = Array.isArray(provider.sources) ? provider.sources : [];
    const available = sources.filter((source) => source.status === "available").length;
    byId("memoryPanel").innerHTML = `
      ${metric("Provider", labels[name] || name)}
      ${metric("Mode", provider.mode || "-")}
      ${metric("Available sources", `${available}/${sources.length}`)}
      <div class="source-list">
        ${sources.map((source) => `
          <div class="source-row">
            <code>${escapeHtml(source.path || source.resolvedPath || "-")}</code>
            ${badge(source.status || "unknown")}
          </div>
        `).join("") || `<p class="muted">No sources are configured for this provider.</p>`}
      </div>
      ${available === 0 ? `<p class="muted">This provider is enabled, but no configured source is currently available in the project.</p>` : ""}
    `;
  };

  byId("runId").textContent = text(state.runId);
  byId("activeRole").textContent = text(state.activeRole);
  byId("projectName").textContent = text(profile.projectName || profile.name || state.projectName || "Unknown");
  byId("updatedAt").textContent = text(state.updatedAtUtc);
  byId("decisionBadge").textContent = text(state.decision, "review");
  byId("decisionBadge").className = `badge status-${text(state.decision, "review")}`;

  const configReportsLoaded = [tokenUsage, contextMemory, integrations].filter(Boolean).length;
  byId("frameworkStatus").textContent = `${configReportsLoaded}/3 reports loaded`;
  byId("configButton").addEventListener("click", openConfigModal);
  byId("configCloseButton").addEventListener("click", closeConfigModal);
  byId("configModal").addEventListener("click", (event) => {
    if (event.target && event.target.hasAttribute("data-close-modal")) {
      closeConfigModal();
    }
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      closeConfigModal();
    }
  });

  document.querySelectorAll("[data-memory-tab]").forEach((button) => {
    button.addEventListener("click", () => renderMemoryTab(button.dataset.memoryTab));
  });
  const configuredMemoryTab = localStorage.getItem("aiSdlcMemoryTab") || "adr";
  renderMemoryTab(configuredMemoryTab);
  byId("memoryStatus").textContent = contextMemory
    ? `${contextMemory.enabledProviders || 0} providers enabled`
    : "No context report loaded";

  if (tokenUsage) {
    byId("tokenDecision").innerHTML = badge(tokenUsage.decision || "review");
    const thresholds = tokenUsage.thresholds || {};
    byId("tokenPanel").innerHTML = [
      metric("Estimated tokens", tokenUsage.estimatedTokens || 0),
      metric("Counted items", Array.isArray(tokenUsage.countedItems) ? tokenUsage.countedItems.length : 0),
      metric("Warning at", thresholds.warningTokens || "-"),
      metric("Review at", thresholds.reviewRequiredTokens || "-"),
      metric("Blocked at", thresholds.blockedTokens || "-")
    ].join("");
  } else {
    byId("tokenPanel").innerHTML = `<p class="muted">No token usage report has been generated yet.</p>`;
  }

  if (contextMemory) {
    byId("contextDecision").innerHTML = badge(contextMemory.decision || "review");
    const providers = Array.isArray(contextMemory.providers) ? contextMemory.providers : [];
    byId("contextPanel").innerHTML = `
      ${metric("Enabled providers", contextMemory.enabledProviders || 0)}
      ${metric("Available sources", contextMemory.availableSources || 0)}
      <ul class="artifact-list">
        ${providers.map((provider) => `<li>${escapeHtml(provider.name)}: ${escapeHtml(provider.enabled ? "on" : "off")} / ${escapeHtml(provider.mode || "-")}</li>`).join("") || "<li class=\"muted\">No providers configured</li>"}
      </ul>
    `;
  } else {
    byId("contextPanel").innerHTML = `<p class="muted">No context memory report has been generated yet.</p>`;
  }

  if (integrations) {
    byId("integrationsDecision").innerHTML = badge(integrations.decision || "review");
    const integrationRows = Array.isArray(integrations.integrations) ? integrations.integrations : [];
    byId("integrationsPanel").innerHTML = `
      ${metric("Enabled", integrations.enabledIntegrations || 0)}
      ${metric("Ready", integrations.readyIntegrations || 0)}
      <ul class="artifact-list">
        ${integrationRows.map((item) => `<li>${escapeHtml(item.name)}: ${escapeHtml(item.status)} ${item.enabled ? badge(item.mode || "on") : ""}</li>`).join("") || "<li class=\"muted\">No integrations configured</li>"}
      </ul>
    `;
  } else {
    byId("integrationsPanel").innerHTML = `<p class="muted">No integrations report has been generated yet.</p>`;
  }

  const roles = Array.isArray(state.roles) ? state.roles : [];
  byId("roleCount").textContent = `${roles.length} roles`;
  byId("roles").innerHTML = roles.map((role) => {
    const artifacts = Array.isArray(role.artifacts) && role.artifacts.length
      ? role.artifacts.map((item) => `<li><code>${escapeHtml(item)}</code></li>`).join("")
      : `<li class="muted">No artifacts yet</li>`;
    const active = role.id === state.activeRole ? " active" : "";
    return `
      <article class="role-card status-${escapeHtml(role.status || "pending")}${active}">
        <div class="role-top">
          <span class="role-title">${escapeHtml(role.title || role.id)}</span>
          ${badge(role.status || "pending")}
        </div>
        <p class="role-purpose">${escapeHtml(role.purpose)}</p>
        <p class="role-message">${escapeHtml(role.message)}</p>
        <ul class="artifact-list">${artifacts}</ul>
      </article>
    `;
  }).join("");

  byId("eventCount").textContent = `${events.length} events`;
  byId("events").innerHTML = events.slice(-120).map((event) => {
    const artifacts = Array.isArray(event.artifacts) ? event.artifacts.join(", ") : "";
    return `
      <tr>
        <td>${escapeHtml(event.timeUtc)}</td>
        <td>${escapeHtml(event.role)}</td>
        <td>${badge(event.status)}</td>
        <td>${escapeHtml(event.message)}</td>
        <td><code>${escapeHtml(artifacts)}</code></td>
      </tr>
    `;
  }).join("");

  if (safety) {
    byId("safetyDecision").innerHTML = `${badge(safety.decision || (safety.passed ? "proceed" : "review_required"))}`;
    const blockers = Array.isArray(safety.blockers) ? safety.blockers : [];
    const warnings = Array.isArray(safety.warnings) ? safety.warnings : [];
    byId("safetyPanel").innerHTML = `
      <p><strong>Passed:</strong> ${escapeHtml(safety.passed)}</p>
      <p><strong>Blockers:</strong> ${blockers.length}</p>
      <ul class="safety-list">${blockers.map((item) => `<li>${escapeHtml(item.code || item.message || item)}</li>`).join("") || "<li class=\"muted\">No blockers</li>"}</ul>
      <p><strong>Warnings:</strong> ${warnings.length}</p>
      <ul class="safety-list">${warnings.map((item) => `<li>${escapeHtml(item.code || item.message || item)}</li>`).join("") || "<li class=\"muted\">No warnings</li>"}</ul>
    `;
  } else {
    byId("safetyPanel").innerHTML = `<p class="muted">No safety report has been generated for this run yet.</p>`;
  }

  const artifactPaths = new Set();
  roles.forEach((role) => {
    (role.artifacts || []).forEach((artifact) => artifactPaths.add(artifact));
  });
  if (summary && summary.reports) {
    Object.keys(summary.reports).forEach((key) => artifactPaths.add(summary.reports[key]));
  }
  byId("artifactCount").textContent = `${artifactPaths.size} artifacts`;
  byId("artifactPanel").innerHTML = artifactPaths.size
    ? `<ul class="artifact-list">${Array.from(artifactPaths).map((item) => `<li><code>${escapeHtml(item)}</code></li>`).join("")}</ul>`
    : `<p class="muted">No artifacts yet.</p>`;

  window.setTimeout(() => {
    if (byId("configModal").hidden && document.visibilityState === "visible") {
      window.location.reload();
    }
  }, 3000);
})();
