"use client";

import { useCallback, useEffect, useState, type ReactNode } from "react";

export interface ActivityItem {
  id: string;
  icon: ReactNode;
  label: string;
  description?: string;
  panel: ReactNode;
}

interface AppShellProps {
  activities: ActivityItem[];
  defaultActivity?: string;
  sidebarWidth?: number;
  topBar?: ReactNode;
  inspector?: ReactNode;
  dock?: ReactNode;
  runtimeStrip?: ReactNode;
  aiSidebar?: ReactNode;
  onToggleAiSidebar?: () => void;
  children?: ReactNode;
  onResetLayout?: () => void;
  onContextMenu?: (event: React.MouseEvent<HTMLDivElement>) => void;
}

export function AppShell({
  activities,
  defaultActivity,
  sidebarWidth = 260,
  topBar,
  inspector,
  dock,
  runtimeStrip,
  aiSidebar,
  onToggleAiSidebar,
  children,
  onResetLayout,
  onContextMenu,
}: AppShellProps) {
  const [activeId, setActiveId] = useState(
    defaultActivity ?? activities[0]?.id,
  );
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [inspectorOpen, setInspectorOpen] = useState(true);
  const [dockOpen, setDockOpen] = useState(true);
  const [sidebarWidthPx, setSidebarWidthPx] = useState(sidebarWidth);
  const [inspectorWidthPx, setInspectorWidthPx] = useState(320);
  const [dockHeightPx, setDockHeightPx] = useState(188);
  const [aiSidebarWidthPx, setAiSidebarWidthPx] = useState(360);
  const [resizing, setResizing] = useState<
    "sidebar" | "inspector" | "dock" | "ai" | null
  >(null);

  useEffect(() => {
    const raw = window.localStorage.getItem("anysim:appshell-layout");
    if (!raw) return;
    try {
      const saved = JSON.parse(raw) as {
        sidebarOpen?: boolean;
        inspectorOpen?: boolean;
        dockOpen?: boolean;
        sidebarWidthPx?: number;
        inspectorWidthPx?: number;
        dockHeightPx?: number;
        aiSidebarWidthPx?: number;
      };
      if (typeof saved.sidebarOpen === "boolean")
        setSidebarOpen(saved.sidebarOpen);
      if (typeof saved.inspectorOpen === "boolean")
        setInspectorOpen(saved.inspectorOpen);
      if (typeof saved.dockOpen === "boolean") setDockOpen(saved.dockOpen);
      if (typeof saved.sidebarWidthPx === "number")
        setSidebarWidthPx(saved.sidebarWidthPx);
      if (typeof saved.inspectorWidthPx === "number")
        setInspectorWidthPx(saved.inspectorWidthPx);
      if (typeof saved.dockHeightPx === "number")
        setDockHeightPx(saved.dockHeightPx);
      if (typeof saved.aiSidebarWidthPx === "number")
        setAiSidebarWidthPx(saved.aiSidebarWidthPx);
    } catch {
      // ignore invalid persisted layout
    }
  }, []);

  useEffect(() => {
    window.localStorage.setItem(
      "anysim:appshell-layout",
      JSON.stringify({
        sidebarOpen,
        inspectorOpen,
        dockOpen,
        sidebarWidthPx,
        inspectorWidthPx,
        dockHeightPx,
        aiSidebarWidthPx,
      }),
    );
  }, [
    sidebarOpen,
    inspectorOpen,
    dockOpen,
    sidebarWidthPx,
    inspectorWidthPx,
    dockHeightPx,
    aiSidebarWidthPx,
  ]);

  const activeActivity = activities.find(
    (activity) => activity.id === activeId,
  );

  const toggleActivity = useCallback(
    (id: string) => {
      if (id === activeId && sidebarOpen) {
        setSidebarOpen(false);
        return;
      }
      setActiveId(id);
      setSidebarOpen(true);
    },
    [activeId, sidebarOpen],
  );

  const installResizeHandlers = useCallback(
    (
      kind: "sidebar" | "inspector" | "dock" | "ai",
      onMove: (event: MouseEvent) => void,
    ) => {
      setResizing(kind);
      const handleMouseUp = () => {
        setResizing(null);
        document.removeEventListener("mousemove", onMove);
        document.removeEventListener("mouseup", handleMouseUp);
      };

      document.addEventListener("mousemove", onMove);
      document.addEventListener("mouseup", handleMouseUp);
    },
    [],
  );

  const handleSidebarMouseDown = useCallback(
    (event: React.MouseEvent) => {
      event.preventDefault();
      installResizeHandlers("sidebar", (moveEvent) => {
        setSidebarWidthPx((prev) =>
          Math.max(220, Math.min(420, prev + moveEvent.movementX)),
        );
      });
    },
    [installResizeHandlers],
  );

  const handleInspectorMouseDown = useCallback(
    (event: React.MouseEvent) => {
      event.preventDefault();
      installResizeHandlers("inspector", (moveEvent) => {
        setInspectorWidthPx((prev) =>
          Math.max(260, Math.min(460, prev - moveEvent.movementX)),
        );
      });
    },
    [installResizeHandlers],
  );

  const handleDockMouseDown = useCallback(
    (event: React.MouseEvent) => {
      event.preventDefault();
      installResizeHandlers("dock", (moveEvent) => {
        setDockHeightPx((prev) =>
          Math.max(120, Math.min(320, prev - moveEvent.movementY)),
        );
      });
    },
    [installResizeHandlers],
  );

  const handleAiSidebarMouseDown = useCallback(
    (event: React.MouseEvent) => {
      event.preventDefault();
      installResizeHandlers("ai", (moveEvent) => {
        setAiSidebarWidthPx((prev) =>
          Math.max(300, Math.min(520, prev - moveEvent.movementX)),
        );
      });
    },
    [installResizeHandlers],
  );

  const handleResetLayout = useCallback(() => {
    setSidebarOpen(true);
    setInspectorOpen(true);
    setDockOpen(true);
    setSidebarWidthPx(sidebarWidth);
    setInspectorWidthPx(320);
    setDockHeightPx(188);
    setAiSidebarWidthPx(360);
    window.localStorage.removeItem("anysim:appshell-layout");
    onResetLayout?.();
  }, [onResetLayout, sidebarWidth]);

  return (
    <div
      className="appshell flex h-screen flex-col overflow-hidden"
      onContextMenu={onContextMenu}
      style={{ background: "var(--chrome-bg)" }}
    >
      {topBar ? <div className="shrink-0">{topBar}</div> : null}

      <div className="flex min-h-0 flex-1 flex-col">
        <div className="flex min-h-0 flex-1">
          <aside
            className="activity-bar hidden w-12 shrink-0 border-r xl:flex xl:flex-col xl:justify-between"
            style={{
              background: "var(--activity-bar-bg)",
              borderColor: "var(--border-color)",
            }}
          >
            <div>
              <nav className="py-1">
                {activities.map((activity) => {
                  const active = activity.id === activeId && sidebarOpen;
                  return (
                    <button
                      key={activity.id}
                      onClick={() => toggleActivity(activity.id)}
                      className="relative flex h-12 w-full items-center justify-center transition"
                      style={{
                        background: active
                          ? "rgba(255,255,255,0.08)"
                          : "transparent",
                        color: active
                          ? "var(--activity-bar-fg)"
                          : "rgba(238,242,248,0.66)",
                      }}
                      title={activity.label}
                    >
                      {active ? (
                        <span className="absolute left-0 top-1/2 h-6 w-0.5 -translate-y-1/2 bg-white" />
                      ) : null}
                      <span>{activity.icon}</span>
                    </button>
                  );
                })}
              </nav>
            </div>

            <div
              className="border-t px-1 py-1"
              style={{ borderColor: "rgba(255,255,255,0.08)" }}
            >
              <button
                onClick={handleResetLayout}
                className="flex h-10 w-full items-center justify-center text-[10px] transition"
                style={{ color: "rgba(238,242,248,0.72)" }}
                title="Reset Layout"
              >
                R
              </button>
            </div>
          </aside>

          {sidebarOpen ? (
            <div
              className="relative hidden shrink-0 overflow-hidden border-r xl:block"
              style={{
                width: sidebarWidthPx,
                background: "var(--panel-bg)",
                borderColor: "var(--border-color)",
              }}
            >
              <div
                className="flex h-9 items-center border-b px-3 text-[11px]"
                style={{
                  borderColor: "var(--border-color)",
                  color: "var(--text-main)",
                }}
              >
                <div className="truncate font-medium">
                  {activeActivity?.label}
                </div>
              </div>
              {activeActivity?.description ? (
                <div
                  className="border-b px-3 py-1.5 text-[10px]"
                  style={{
                    borderColor: "var(--border-color)",
                    color: "var(--text-secondary)",
                    background: "var(--panel-subtle)",
                  }}
                >
                  {activeActivity.description}
                </div>
              ) : null}
              <div className="h-[calc(100%-36px)] overflow-auto px-2 py-2">
                {activeActivity?.panel}
              </div>
              <div
                className="absolute right-0 top-0 h-full w-1 cursor-col-resize"
                style={{
                  background:
                    resizing === "sidebar" ? "var(--accent)" : "transparent",
                }}
                onMouseDown={handleSidebarMouseDown}
              />
            </div>
          ) : null}

          <div className="flex min-w-0 flex-1">
            <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
              <main
                className="workspace flex min-h-0 min-w-0 flex-1 overflow-hidden"
                style={{ background: "var(--workspace-bg)" }}
              >
                {children}
              </main>

              {dock ? (
                dockOpen ? (
                  <div
                    className="relative shrink-0 border-t"
                    style={{
                      height: dockHeightPx,
                      borderColor: "var(--border-color)",
                      background: "var(--panel-bg)",
                    }}
                  >
                    <div
                      className="absolute left-0 top-0 h-1 w-full cursor-row-resize"
                      style={{
                        background:
                          resizing === "dock" ? "var(--accent)" : "transparent",
                      }}
                      onMouseDown={handleDockMouseDown}
                    />

                    <button
                      onClick={() => setDockOpen(false)}
                      className="absolute right-2 top-2 z-10 text-[11px]"
                      style={{ color: "var(--text-secondary)" }}
                      title="Hide Output"
                    >
                      ×
                    </button>
                    {runtimeStrip ? (
                      <div className="pointer-events-none absolute left-1/2 top-0 z-10 -translate-x-1/2 -translate-y-full">
                        {runtimeStrip}
                      </div>
                    ) : null}
                    <div className="h-full overflow-hidden pt-1">{dock}</div>
                  </div>
                ) : (
                  <div
                    className="flex h-8 shrink-0 items-center justify-between border-t px-3 text-[11px]"
                    style={{
                      borderColor: "var(--border-color)",
                      background: "var(--panel-bg)",
                      color: "var(--text-secondary)",
                    }}
                  >
                    <span>Output collapsed</span>
                    <button
                      onClick={() => setDockOpen(true)}
                      style={{ color: "var(--text-main)" }}
                    >
                      Open
                    </button>
                  </div>
                )
              ) : null}
            </div>

            {inspector && inspectorOpen ? (
              <aside
                className="relative hidden shrink-0 overflow-hidden border-r 2xl:block"
                style={{
                  width: inspectorWidthPx,
                  background: "var(--panel-bg)",
                  borderColor: "var(--border-color)",
                }}
              >
                <div
                  className="flex h-9 items-center justify-between border-b px-3 text-[11px]"
                  style={{
                    borderColor: "var(--border-color)",
                    color: "var(--text-main)",
                  }}
                >
                  <span className="font-medium">Inspector</span>
                  <button
                    onClick={() => setInspectorOpen(false)}
                    className="text-[12px]"
                    style={{ color: "var(--text-secondary)" }}
                    title="Hide Inspector"
                  >
                    ×
                  </button>
                </div>
                <div className="h-[calc(100%-36px)] overflow-hidden">
                  {inspector}
                </div>
                <div
                  className="absolute left-0 top-0 h-full w-1 cursor-col-resize"
                  style={{
                    background:
                      resizing === "inspector"
                        ? "var(--accent)"
                        : "transparent",
                  }}
                  onMouseDown={handleInspectorMouseDown}
                />
              </aside>
            ) : null}

            {aiSidebar ? (
              <aside
                className="relative shrink-0 overflow-hidden border-l"
                style={{
                  width: aiSidebarWidthPx,
                  background: "var(--panel-bg)",
                  borderColor: "var(--border-color)",
                }}
              >
                <div
                  className="absolute left-0 top-0 h-full w-1 cursor-col-resize"
                  style={{
                    background:
                      resizing === "ai" ? "var(--accent)" : "transparent",
                  }}
                  onMouseDown={handleAiSidebarMouseDown}
                />

                <div
                  className="flex h-9 items-center justify-between border-b px-3 text-[11px]"
                  style={{
                    borderColor: "var(--border-color)",
                    color: "var(--text-main)",
                  }}
                >
                  <span className="font-medium">AI Assistant</span>
                  <button
                    onClick={onToggleAiSidebar}
                    className="text-[12px]"
                    style={{ color: "var(--text-secondary)" }}
                    title="Hide AI Sidebar"
                  >
                    ×
                  </button>
                </div>
                <div className="h-[calc(100%-36px)] overflow-hidden">
                  {aiSidebar}
                </div>
              </aside>
            ) : onToggleAiSidebar ? (
              <button
                onClick={onToggleAiSidebar}
                className="hidden w-8 shrink-0 items-center justify-center border-l text-[10px] 2xl:flex"
                style={{
                  background: "var(--panel-bg)",
                  borderColor: "var(--border-color)",
                  color: "var(--text-secondary)",
                }}
                title="Open AI Sidebar"
              >
                <span className="[writing-mode:vertical-rl]">AI</span>
              </button>
            ) : null}
          </div>
        </div>
      </div>
    </div>
  );
}

export function IconModel() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M4 7 12 3l8 4-8 4-8-4Z" />
      <path d="M4 12l8 4 8-4" />
      <path d="M4 17l8 4 8-4" />
      <path d="M12 7v14" />
    </svg>
  );
}

export function IconPlay() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <circle cx="12" cy="12" r="8.5" />
      <path d="m10 8 6 4-6 4V8Z" fill="currentColor" stroke="none" />
    </svg>
  );
}

export function IconConfig() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M12 3v4" />
      <path d="M12 17v4" />
      <path d="M4.9 6.2 7.7 9" />
      <path d="m16.3 15 2.8 2.8" />
      <path d="M3 12h4" />
      <path d="M17 12h4" />
      <path d="m4.9 17.8 2.8-2.8" />
      <path d="M16.3 9 19 6.2" />
      <circle cx="12" cy="12" r="3.5" />
    </svg>
  );
}

export function IconChart() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M4 19h16" />
      <path d="M7 16V9" />
      <path d="M12 16V5" />
      <path d="M17 16v-4" />
      <path d="m5 13 5-4 4 2 5-4" />
    </svg>
  );
}

export function IconAi() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M12 3v3" />
      <path d="M12 18v3" />
      <path d="M5.64 5.64 7.76 7.76" />
      <path d="m16.24 16.24 2.12 2.12" />
      <path d="M3 12h3" />
      <path d="M18 12h3" />
      <path d="m5.64 18.36 2.12-2.12" />
      <path d="m16.24 7.76 2.12-2.12" />
      <path d="M9 9h6v6H9z" />
    </svg>
  );
}

export interface WorkspaceTab {
  id: string;
  label: string;
  content: ReactNode;
  closable?: boolean;
}

interface WorkspaceTabsProps {
  tabs: WorkspaceTab[];
  activeTab: string;
  onTabChange: (id: string) => void;
  onTabClose?: (id: string) => void;
}

export function WorkspaceTabs({
  tabs,
  activeTab,
  onTabChange,
  onTabClose,
}: WorkspaceTabsProps) {
  return (
    <div className="workspace-tabs flex h-full flex-col">
      <div
        className="flex h-9 items-end overflow-x-auto border-b"
        style={{
          borderColor: "var(--border-color)",
          background: "var(--panel-subtle)",
        }}
      >
        {tabs.map((tab) => {
          const active = tab.id === activeTab;
          return (
            <button
              key={tab.id}
              onClick={() => onTabChange(tab.id)}
              className="flex h-9 items-center gap-2 border-r px-3 text-[12px] transition"
              style={{
                borderColor: "var(--border-color)",
                background: active ? "var(--workspace-bg)" : "transparent",
                color: active ? "var(--text-main)" : "var(--text-secondary)",
              }}
            >
              <span className="font-medium">{tab.label}</span>
              {tab.closable && onTabClose ? (
                <span
                  onClick={(event) => {
                    event.stopPropagation();
                    onTabClose(tab.id);
                  }}
                  className="text-[10px]"
                >
                  ×
                </span>
              ) : null}
            </button>
          );
        })}
      </div>
      <div className="min-h-0 flex-1 overflow-auto">
        {tabs.find((tab) => tab.id === activeTab)?.content}
      </div>
    </div>
  );
}
