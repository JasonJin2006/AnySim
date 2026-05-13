"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type MouseEvent as ReactMouseEvent,
} from "react";
import {
  AppShell,
  IconAi,
  IconChart,
  IconConfig,
  IconModel,
  IconPlay,
} from "@/components/AppShell";
import { ControlPanel } from "@/components/ControlPanel";
import { StatusBar } from "@/components/StatusBar";
import {
  ConnectOverlay,
  WorkbenchContextMenu,
} from "@/components/workbench-overlays";
import { WorkbenchTopBar } from "@/components/workbench-shell";
import {
  EventsPanel,
  ExplorerPanel,
  ExtensionDockPanel,
  ExtensionLibraryPanel,
  InspectorPanel,
  LogsPanel,
  ProblemsPanel,
  ProjectFilesPanel,
  SearchPanel,
  SimulationTreePanel,
  SourceControlPanel,
  WorkbenchDock,
} from "@/components/workbench-panels";
import {
  WorkbenchSurface,
  type WorkbenchPage,
} from "@/components/workbench-surface";
import { getExtensionById, getPresetById } from "@/extensions/registry";
import type { ExtensionRuntimeContext } from "@/extensions/types";
import { useSimulation, type SimMode } from "@/hooks/useSimulation";
import {
  getShippingProjectFileById,
  getShippingProjectScenarioById,
  shippingProjectFiles,
  shippingProjectManifest,
  shippingProjectRoot,
  shippingProjectScenarios,
} from "@/lib/shipping-project";

type DockTab = "events" | "shipping-kpi" | "logs" | "problems";

function buildExtensionPage(viewId: string, label: string): WorkbenchPage {
  return {
    id: viewId,
    kind: "extension",
    title: label,
    subtitle: "shipping view",
    viewId,
  };
}

function buildDocumentPage(
  fileId: string,
  label: string,
  subtitle: string,
): WorkbenchPage {
  return {
    id: `file:${fileId}`,
    kind: "document",
    title: label,
    subtitle,
    fileId,
  };
}

export default function HomePage() {
  const sim = useSimulation();
  const [dockTab, setDockTab] = useState<DockTab>("events");
  const [showConnectDialog, setShowConnectDialog] = useState(!sim.connected);
  const [showAiSidebar, setShowAiSidebar] = useState(false);
  const [parameterDrafts, setParameterDrafts] = useState<
    Record<string, Record<string, string>>
  >({});
  const [contextMenu, setContextMenu] = useState<{
    x: number;
    y: number;
    scope: string;
  } | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [activeScenarioId, setActiveScenarioId] = useState(
    shippingProjectScenarios[1]?.id ??
      shippingProjectScenarios[0]?.id ??
      "baseline",
  );
  const [pages, setPages] = useState<WorkbenchPage[]>([
    {
      id: "canvas",
      kind: "canvas",
      title: "Canvas",
      subtitle: "shipping composition",
    },
    { id: "code", kind: "code", title: "Code", subtitle: "source of truth" },
  ]);
  const [activePageId, setActivePageId] = useState<string>("canvas");

  const handleModeChange = useCallback(
    (mode: SimMode) => {
      sim.setMode(mode);
    },
    [sim],
  );

  const handleReconnect = useCallback(() => {
    setShowConnectDialog(true);
  }, []);

  const entityRows = useMemo(
    () => Array.from(sim.entityCache.getAllEntities().entries()),
    [sim.entityCache, sim.stepCount],
  );
  const modelEntities = sim.modelEntities?.entities ?? [];
  const [selectedEntityName, setSelectedEntityName] = useState<string | null>(
    null,
  );

  const selectedEntity =
    modelEntities.find((entity) => entity.name === selectedEntityName) ??
    modelEntities[0] ??
    null;
  const selectedRuntimeEntity =
    entityRows.find(([name]) => name === selectedEntityName) ??
    entityRows.find(([name]) => name === selectedEntity?.name) ??
    entityRows[0] ??
    null;

  const activePreset = sim.activePresetId
    ? getPresetById(sim.activePresetId)
    : getPresetById(shippingProjectManifest.entrypoint.preset_id);
  const activeExtension = activePreset
    ? getExtensionById(activePreset.extensionId)
    : null;
  const activeScenario = getShippingProjectScenarioById(activeScenarioId);
  const activeFileId = activePageId.startsWith("file:")
    ? activePageId.replace("file:", "")
    : null;
  const parameterDirty = Object.keys(parameterDrafts).length > 0;

  const extensionContext = useMemo<ExtensionRuntimeContext | null>(() => {
    if (!activeExtension) return null;
    return {
      extensionId: activeExtension?.id ?? undefined,
      presetId: sim.activePresetId ?? activePreset?.id ?? undefined,
      modelName: sim.modelEntities?.model_name,
      modelEntities: sim.modelEntities,
      entityCache: sim.entityCache,
      outputPorts: sim.outputPorts,
      runner: {
        running: sim.running,
        paused: sim.paused,
        currentTime: sim.currentTime,
        stepCount: sim.stepCount,
        speed: sim.speed,
      },
    };
  }, [
    activeExtension,
    activePreset?.id,
    sim.activePresetId,
    sim.modelEntities,
    sim.entityCache,
    sim.outputPorts,
    sim.running,
    sim.paused,
    sim.currentTime,
    sim.stepCount,
    sim.speed,
  ]);

  const workspaceExtensionViews = useMemo(() => {
    if (!activeExtension || !extensionContext) return [];
    return activeExtension.views.filter(
      (view) =>
        view.placement === "workspace" && view.supports(extensionContext),
    );
  }, [activeExtension, extensionContext]);

  const dockExtensionViews = useMemo(() => {
    if (!activeExtension || !extensionContext) return [];
    return activeExtension.views.filter(
      (view) => view.placement === "dock" && view.supports(extensionContext),
    );
  }, [activeExtension, extensionContext]);

  // 连接后自动加载默认 preset
  useEffect(() => {
    if (!sim.connected) return;
    sim.fetchPresets();
    sim.fetchEntities();
    sim.fetchOutputs();
    // 如果没有活跃 preset，自动加载默认场景
    if (!sim.activePresetId && !sim.modelEntities) {
      const defaultPresetId = shippingProjectManifest.entrypoint.preset_id;
      const defaultScenario =
        shippingProjectScenarios[1] ?? shippingProjectScenarios[0];
      sim.loadPreset(defaultPresetId, defaultScenario?.config);
    }
  }, [
    sim.connected,
    sim.fetchEntities,
    sim.fetchOutputs,
    sim.fetchPresets,
    sim.activePresetId,
    sim.modelEntities,
  ]);

  // Extension views are available but not auto-added to the tab bar.
  // Users can open them from the sidebar if needed.

  useEffect(() => {
    if (!selectedEntityName && modelEntities[0]?.name) {
      setSelectedEntityName(modelEntities[0].name);
    }
  }, [modelEntities, selectedEntityName]);

  const getParameterDraft = useCallback(
    (entityName: string, parameterName: string, fallbackType: string) => {
      return parameterDrafts[entityName]?.[parameterName] ?? fallbackType;
    },
    [parameterDrafts],
  );

  const handleParameterDraftChange = useCallback(
    (entityName: string, parameterName: string, value: string) => {
      setParameterDrafts((prev) => ({
        ...prev,
        [entityName]: {
          ...(prev[entityName] ?? {}),
          [parameterName]: value,
        },
      }));
    },
    [],
  );

  const openPage = useCallback((page: WorkbenchPage) => {
    setPages((prev) =>
      prev.some((entry) => entry.id === page.id) ? prev : [...prev, page],
    );
    setActivePageId(page.id);
  }, []);

  const openFile = useCallback(
    (fileId: string) => {
      const file = getShippingProjectFileById(fileId);
      if (!file) return;
      openPage(
        buildDocumentPage(
          file.id,
          file.label,
          file.path.replace(`${shippingProjectRoot}/`, ""),
        ),
      );
    },
    [openPage],
  );

  const openScenario = useCallback(
    (scenarioId: string) => {
      const scenario = getShippingProjectScenarioById(scenarioId);
      if (!scenario) return;
      const fileId = `scenario-${scenarioId}`;
      openFile(fileId);
    },
    [openFile],
  );

  const openExtensionView = useCallback(
    (viewId: string) => {
      const view =
        workspaceExtensionViews.find((entry) => entry.id === viewId) ??
        activeExtension?.views.find((entry) => entry.id === viewId);
      if (!view) return;
      openPage(buildExtensionPage(view.id, view.label));
    },
    [activeExtension?.views, openPage, workspaceExtensionViews],
  );

  const handleSelectPage = useCallback((pageId: string) => {
    setActivePageId(pageId);
  }, []);

  const handleClosePage = useCallback(
    (pageId: string) => {
      setPages((prev) => {
        const next = prev.filter((page) => page.id !== pageId);
        if (pageId === activePageId) {
          const fallback = next[next.length - 1] ?? next[0] ?? null;
          setActivePageId(fallback?.id ?? "canvas");
        }
        return next;
      });
    },
    [activePageId],
  );

  const handleApplyScenario = useCallback(
    (scenarioId: string) => {
      const scenario = getShippingProjectScenarioById(scenarioId);
      if (!scenario) return;
      setActiveScenarioId(scenario.id);
      // preset_id 格式: "project_id::scenario_id"
      const presetId = `${shippingProjectManifest.project_id}::${scenarioId}`;
      sim.loadPreset(presetId, scenario.config);
      openScenario(scenario.id);
    },
    [openScenario, sim],
  );

  const handleApplyDrafts = useCallback(() => {
    const payload = Object.entries(parameterDrafts).reduce<
      Record<string, Record<string, unknown>>
    >((acc, [entityName, values]) => {
      acc[entityName] = Object.fromEntries(
        Object.entries(values).map(([key, value]) => {
          const trimmed = value.trim();
          if (trimmed === "true") return [key, true];
          if (trimmed === "false") return [key, false];
          if (trimmed !== "" && !Number.isNaN(Number(trimmed)))
            return [key, Number(trimmed)];
          return [key, value];
        }),
      );
      return acc;
    }, {});

    if (Object.keys(payload).length === 0) return;
    sim.setConfig(payload);
    setParameterDrafts({});
  }, [parameterDrafts, sim]);

  const handleOpenCode = useCallback(() => {
    setActivePageId("code");
  }, []);

  const openContextMenu = useCallback(
    (event: ReactMouseEvent<HTMLDivElement>) => {
      event.preventDefault();
      setContextMenu({
        x: event.clientX,
        y: event.clientY,
        scope: "workbench",
      });
    },
    [],
  );

  useEffect(() => {
    const close = () => setContextMenu(null);
    window.addEventListener("click", close);
    window.addEventListener("blur", close);
    window.addEventListener("scroll", close, true);
    return () => {
      window.removeEventListener("click", close);
      window.removeEventListener("blur", close);
      window.removeEventListener("scroll", close, true);
    };
  }, []);

  const activities = [
    {
      id: "explorer",
      icon: <IconModel />,
      label: "Explorer",
      description: "Project structure, scenarios and shipping components.",
      panel: (
        <ExplorerPanel
          modelName={sim.modelEntities?.model_name}
          modelEntities={modelEntities}
          connected={sim.connected}
          selectedEntityName={selectedEntity?.name ?? null}
          activeScenarioId={activeScenarioId}
          scenarios={shippingProjectScenarios}
          onFetch={() => {
            sim.fetchPresets();
            sim.fetchEntities();
            sim.fetchOutputs();
          }}
          onSelectEntity={(name) => {
            setSelectedEntityName(name);
            setActivePageId("canvas");
          }}
          onOpenScenario={openScenario}
          onApplyScenario={handleApplyScenario}
        />
      ),
    },
    {
      id: "files",
      icon: <IconChart />,
      label: "Files",
      description: "Project manifest, docs and scenario files.",
      panel: (
        <ProjectFilesPanel
          connected={sim.connected}
          projectPath={sim.projectPath ?? shippingProjectRoot}
          activePresetId={
            sim.activePresetId ?? shippingProjectManifest.entrypoint.preset_id
          }
          presets={
            sim.presets.length > 0
              ? sim.presets
              : (activeExtension?.presets.map((preset) => ({
                  id: preset.id,
                  label: preset.label,
                  description: preset.description,
                })) ?? [])
          }
          activeExtensionLabel={activeExtension?.label ?? "Liner Shipping"}
          files={shippingProjectFiles}
          activeFileId={activeFileId}
          onLoadPreset={(presetId) =>
            sim.loadPreset(presetId, activeScenario?.config)
          }
          onOpenFile={openFile}
        />
      ),
    },
    {
      id: "search",
      icon: <IconPlay />,
      label: "Search",
      description: "Project-wide file and scenario search.",
      panel: (
        <SearchPanel
          files={shippingProjectFiles}
          query={searchQuery}
          onQueryChange={setSearchQuery}
          onOpenResult={openFile}
        />
      ),
    },
    {
      id: "git",
      icon: <IconConfig />,
      label: "Git",
      description: "Review shipping project files and scenario-level changes.",
      panel: (
        <SourceControlPanel
          files={shippingProjectFiles}
          activeFileId={activeFileId}
          currentScenarioId={activeScenarioId}
        />
      ),
    },
    {
      id: "extensions",
      icon: <IconAi />,
      label: "Extensions",
      description: "Shipping, solver and future template libraries.",
      panel: (
        <ExtensionLibraryPanel
          connected={sim.connected}
          hasErrors={Boolean(sim.error)}
        />
      ),
    },
    {
      id: "tree",
      icon: <IconChart />,
      label: "Sim Tree",
      description:
        "Simulation structure organized by the shipping DSL and extension views.",
      panel: (
        <SimulationTreePanel
          extensionViews={activeExtension?.views ?? []}
          outputPorts={sim.outputPorts}
          selectedEntityName={selectedEntity?.name ?? null}
          activePageId={activePageId}
          onOpenView={openExtensionView}
          onSelectEntity={(name) => {
            setSelectedEntityName(name);
            setActivePageId("canvas");
          }}
        />
      ),
    },
  ];

  const handleResetLayout = useCallback(() => {
    window.localStorage.removeItem("anysim:workbench-layout");
    window.location.reload();
  }, []);

  return (
    <div className="h-screen overflow-hidden">
      <AppShell
        activities={activities}
        onContextMenu={openContextMenu}
        defaultActivity="explorer"
        topBar={
          <WorkbenchTopBar
            onToggleAi={() => setShowAiSidebar((prev) => !prev)}
          />
        }
        inspector={
          <InspectorPanel
            connected={sim.connected}
            modelName={sim.modelEntities?.model_name}
            mode={sim.mode}
            entityCount={sim.entityCache.entityCount}
            selectedEntity={selectedEntity}
            selectedRuntimeEntity={selectedRuntimeEntity}
            activeScenario={activeScenario}
            projectSummary="shipping-liner-demo"
            outputPorts={sim.outputPorts}
            parameterDirty={parameterDirty}
            getParameterDraft={getParameterDraft}
            onParameterDraftChange={handleParameterDraftChange}
            onApplyConfig={handleApplyDrafts}
          />
        }
        runtimeStrip={
          <ControlPanel
            running={sim.running}
            paused={sim.paused}
            speed={sim.speed}
            mode={sim.mode}
            currentTime={sim.currentTime}
            stepCount={sim.stepCount}
            onStart={() => {
              if (!sim.connected) {
                setShowConnectDialog(true);
                return;
              }
              sim.start();
            }}
            onPause={sim.pause}
            onResume={sim.resume}
            onReset={sim.reset}
            onStep={sim.step}
            onSpeedChange={sim.setSpeed}
            onModeChange={handleModeChange}
            disabled={!sim.connected}
          />
        }
        dock={
          <WorkbenchDock
            activeTab={dockTab}
            onTabChange={(tab) => setDockTab(tab as DockTab)}
            extraTabs={[
              {
                id: "shipping-kpi",
                label: "Shipping KPI",
                content: (
                  <ExtensionDockPanel
                    context={extensionContext}
                    extensionViews={dockExtensionViews}
                  />
                ),
              },
            ]}
            eventsPanel={
              <div className="space-y-2">
                <StatusBar
                  connectionStatus={sim.connectionStatus}
                  running={sim.running}
                  paused={sim.paused}
                  currentTime={sim.currentTime}
                  stepCount={sim.stepCount}
                  speed={sim.speed}
                  entityCount={sim.entityCache.entityCount}
                  modelName={sim.modelEntities?.model_name}
                  onReconnect={handleReconnect}
                />

                <EventsPanel runtimeEntities={entityRows} />
              </div>
            }
            logsPanel={
              <LogsPanel connected={sim.connected} error={sim.error} />
            }
            problemsPanel={
              <ProblemsPanel
                error={sim.error}
                connected={sim.connected}
                modelLoaded={Boolean(sim.modelEntities)}
              />
            }
          />
        }
        aiSidebar={
          showAiSidebar ? (
            <AiWorkspace
              connected={sim.connected}
              error={sim.error}
              onOpenCode={handleOpenCode}
            />
          ) : undefined
        }
        onToggleAiSidebar={() => setShowAiSidebar((prev) => !prev)}
        onResetLayout={handleResetLayout}
      >
        <WorkbenchSurface
          modelName={sim.modelEntities?.model_name}
          modelEntities={modelEntities}
          runtimeEntities={entityRows}
          getParameterDraft={getParameterDraft}
          selectedEntity={selectedEntity}
          selectedRuntimeEntity={selectedRuntimeEntity}
          onSelectEntity={setSelectedEntityName}
          connected={sim.connected}
          error={sim.error}
          onConnect={() => setShowConnectDialog(true)}
          pages={pages}
          activePageId={activePageId}
          onSelectPage={handleSelectPage}
          onClosePage={handleClosePage}
          files={shippingProjectFiles}
          activeScenario={activeScenario}
          extensionViews={workspaceExtensionViews}
          extensionContext={extensionContext}
          projectLabel={shippingProjectManifest.name}
        />
      </AppShell>

      {contextMenu ? (
        <WorkbenchContextMenu
          x={contextMenu.x}
          y={contextMenu.y}
          scope={contextMenu.scope}
          onClose={() => setContextMenu(null)}
          onAction={(action) => {
            if (action === "reset-layout") handleResetLayout();
            if (action === "open-connect") setShowConnectDialog(true);
            setContextMenu(null);
          }}
        />
      ) : null}

      {showConnectDialog ? (
        <ConnectOverlay
          presets={sim.presets}
          activePresetId={sim.activePresetId}
          onLoadPreset={(presetId) =>
            sim.loadPreset(presetId, activeScenario?.config)
          }
          onConnect={(url) => {
            sim.connect(url);
            setShowConnectDialog(false);
          }}
          onClose={() => setShowConnectDialog(false)}
        />
      ) : null}
    </div>
  );
}

function AiWorkspace({
  connected,
  error,
  onOpenCode,
}: {
  connected: boolean;
  error: string | null;
  onOpenCode: () => void;
}) {
  return (
    <div
      className="flex h-full flex-col"
      style={{ background: "var(--panel-bg)", color: "var(--text-main)" }}
    >
      <div
        className="flex h-10 items-center justify-between border-b px-3 text-[11px]"
        style={{ borderColor: "var(--border-color)" }}
      >
        <span className="font-medium">New Conversation</span>
        <div
          className="flex items-center gap-3"
          style={{ color: "var(--text-secondary)" }}
        >
          <button>新建</button>
          <button>历史</button>
          <button>设置</button>
        </div>
      </div>

      <div className="min-h-0 flex-1 overflow-auto p-4">
        <div
          className="border p-4"
          style={{
            borderColor: "var(--border-color)",
            background: "var(--workspace-bg)",
          }}
        >
          <div className="text-[12px]" style={{ color: "var(--text-main)" }}>
            AI 助手已准备就绪
          </div>
          <p
            className="mt-2 text-[11px] leading-6"
            style={{ color: "var(--text-secondary)" }}
          >
            {connected
              ? "现在可以基于 shipping 项目的场景配置、仿真结构、运行状态和输出端口继续做建模与分析。"
              : "当前可以讨论项目结构与建模方案；连接运行时后可进一步读取状态变量和输出结果。"}
          </p>
          {error ? (
            <div
              className="mt-3 border px-3 py-2 text-[11px]"
              style={{
                borderColor: "rgba(224,49,49,0.4)",
                background: "rgba(224,49,49,0.08)",
                color: "#ffb4b4",
              }}
            >
              当前错误：{error}
            </div>
          ) : null}
          <button
            onClick={onOpenCode}
            className="mt-3 border px-3 py-1.5 text-[11px] transition"
            style={{
              borderColor: "var(--border-color)",
              color: "var(--text-main)",
            }}
          >
            打开 Code 页面
          </button>
        </div>
      </div>

      <div
        className="border-t p-3"
        style={{ borderColor: "var(--border-color)" }}
      >
        <div
          className="border px-3 py-2"
          style={{
            borderColor: "var(--border-color)",
            background: "var(--workspace-bg)",
          }}
        >
          <div
            className="text-[11px]"
            style={{ color: "var(--text-secondary)" }}
          >
            输入你的建模需求、诊断问题或运行分析...
          </div>
        </div>
        <div
          className="mt-2 flex items-center justify-between text-[10px]"
          style={{ color: "var(--text-secondary)" }}
        >
          <div className="flex items-center gap-3">
            <button>构建模式</button>
            <button>聊天模式</button>
          </div>
          <button style={{ color: "var(--text-main)" }}>发送</button>
        </div>
      </div>
    </div>
  );
}
