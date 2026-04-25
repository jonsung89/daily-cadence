const { useState } = React;

const TYPE_COLORS_W = {
  workout:  { dot: "var(--dc-workout)",  label: "Workout",  icon: "dumbbell" },
  meal:     { dot: "var(--dc-meal)",     label: "Meal",     icon: "utensils" },
  sleep:    { dot: "var(--dc-sleep)",    label: "Sleep",    icon: "moon" },
  mood:     { dot: "var(--dc-mood)",     label: "Mood",     icon: "smile" },
  activity: { dot: "var(--dc-activity)", label: "Activity", icon: "footprints" },
};

const Icn = ({ name, style }) => <i data-lucide={name} style={style} />;

const Sidebar = ({ active, onNav }) => {
  const nav = [
    { id: "dashboard", icon: "layout-grid", label: "Dashboard" },
    { id: "timeline",  icon: "clock",       label: "Timeline", count: "6" },
    { id: "calendar",  icon: "calendar",    label: "Calendar" },
    { id: "analytics", icon: "bar-chart-3", label: "Analytics" },
  ];
  const lib = [
    { id: "workouts", icon: "dumbbell",   label: "Workouts" },
    { id: "meals",    icon: "utensils",   label: "Meals" },
    { id: "sleep",    icon: "moon",       label: "Sleep" },
    { id: "notes",    icon: "sticky-note",label: "All notes", count: "248" },
  ];
  return (
    <nav className="sidebar">
      <div className="brand"><div className="mark"></div><div className="name">Daily Cadence</div></div>
      <button className="btn primary" style={{margin:"4px 8px 14px", justifyContent:"center"}}><Icn name="plus" /> New note</button>
      <div className="nav-section">Overview</div>
      {nav.map(n => (
        <button key={n.id} className={"nav-item" + (active === n.id ? " active" : "")} onClick={() => onNav(n.id)}>
          <Icn name={n.icon} /> {n.label} {n.count && <span className="count">{n.count}</span>}
        </button>
      ))}
      <div className="nav-section">Library</div>
      {lib.map(n => (
        <button key={n.id} className={"nav-item" + (active === n.id ? " active" : "")} onClick={() => onNav(n.id)}>
          <Icn name={n.icon} /> {n.label} {n.count && <span className="count">{n.count}</span>}
        </button>
      ))}
      <div className="sidebar-footer">
        <div className="avatar">SK</div>
        <div className="who"><div className="nm">Sam Kent</div><div className="pl">Free plan</div></div>
      </div>
    </nav>
  );
};

const LineChart = ({ data, color = "var(--dc-sage)", height = 180, showAxis = true }) => {
  const w = 600, h = height, pad = 28;
  const min = Math.min(...data) - 0.5, max = Math.max(...data) + 0.5;
  const stepX = (w - pad * 2) / (data.length - 1);
  const points = data.map((v, i) => [pad + i * stepX, pad + (1 - (v - min) / (max - min)) * (h - pad * 2)]);
  const path = points.map(([x, y], i) => (i === 0 ? `M${x},${y}` : `L${x},${y}`)).join(" ");
  const area = path + ` L${points[points.length-1][0]},${h-pad} L${pad},${h-pad} Z`;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} width="100%" style={{display:"block"}}>
      {[0,1,2,3].map(i => {
        const y = pad + i * (h - pad * 2) / 3;
        return <line key={i} x1={pad} x2={w-pad} y1={y} y2={y} stroke="var(--border-1)" strokeDasharray="2 4" />;
      })}
      <path d={area} fill={color} opacity="0.12" />
      <path d={path} fill="none" stroke={color} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
      {points.map(([x,y], i) => (i === points.length - 1 ? (
        <g key={i}><circle cx={x} cy={y} r="10" fill={color} opacity="0.15" /><circle cx={x} cy={y} r="4" fill={color} stroke="var(--bg-2)" strokeWidth="2" /></g>
      ) : null))}
    </svg>
  );
};

Object.assign(window, { TYPE_COLORS_W, Icn, Sidebar, LineChart });
