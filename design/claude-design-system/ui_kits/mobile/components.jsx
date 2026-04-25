// Shared primitives for the mobile UI kit
const { useState } = React;

const Icon = ({ name, size = 22, color, strokeWidth = 1.75, style }) => {
  return <i data-lucide={name} style={{ width: size, height: size, color, strokeWidth, display: "inline-flex", ...style }} />;
};

// Semantic note types — natural pigments, resolved from CSS tokens
// so they follow light/dark mode automatically. Keys match token suffixes.
const TYPE_COLORS = {
  workout:  { dot: "var(--dc-workout)",  soft: "var(--dc-workout-soft)",  icon: "dumbbell",   label: "Workout"  }, // clay
  meal:     { dot: "var(--dc-meal)",     soft: "var(--dc-meal-soft)",     icon: "utensils",   label: "Meal"     }, // turmeric
  sleep:    { dot: "var(--dc-sleep)",    soft: "var(--dc-sleep-soft)",    icon: "moon",       label: "Sleep"    }, // dusk
  mood:     { dot: "var(--dc-mood)",     soft: "var(--dc-mood-soft)",     icon: "smile",      label: "Mood"     }, // plum
  activity: { dot: "var(--dc-activity)", soft: "var(--dc-activity-soft)", icon: "footprints", label: "Activity" }, // moss
};

const NoteCard = ({ type, time, title, body }) => {
  const t = TYPE_COLORS[type];
  return (
    <div className="note">
      <div className="head">
        <span className="dot" style={{ background: t.dot }}></span>
        {t.label}
        <span className="time">{time}</span>
      </div>
      <div className="title">{title}</div>
      {body && <div className="body">{body}</div>}
    </div>
  );
};

const TimelineItem = ({ time, type, title, body }) => {
  const t = TYPE_COLORS[type];
  return (
    <div className="tl-item">
      <span className="t">{time}</span>
      <span className="d" style={{ background: t.dot }}></span>
      <NoteCard type={type} time={time} title={title} body={body} />
    </div>
  );
};

const Phone = ({ children }) => (
  <div className="phone">
    <div className="notch" />
    <div className="statusbar">
      <span>9:41</span>
      <div className="right">
        <Icon name="signal" size={16} /> <Icon name="wifi" size={16} /> <Icon name="battery-full" size={20} />
      </div>
    </div>
    {children}
  </div>
);

const TabBar = ({ active, onNav }) => {
  const tabs = [
    { id: "timeline", icon: "home", label: "Today" },
    { id: "calendar", icon: "calendar", label: "Calendar" },
    { id: "chart",    icon: "bar-chart-3", label: "Progress" },
    { id: "dashboard",icon: "layout-grid", label: "Dashboard" },
    { id: "settings", icon: "user", label: "Profile" },
  ];
  return (
    <div className="tabbar">
      {tabs.map(t => (
        <button key={t.id} className={"tab" + (active === t.id ? " active" : "")} onClick={() => onNav(t.id)}>
          <Icon name={t.icon} size={22} color={active === t.id ? "var(--dc-sage-deep)" : "var(--fg-2)"} />
          <span>{t.label}</span>
          {active === t.id && <span className="dot" />}
        </button>
      ))}
    </div>
  );
};

const TopBar = ({ title, sub, left, right }) => (
  <div className="topbar">
    <div>
      {sub && <div className="sub">{sub}</div>}
      <h1>{title}</h1>
    </div>
    <div style={{display:"flex",gap:4}}>
      {left}
      {right}
    </div>
  </div>
);

Object.assign(window, { Icon, TYPE_COLORS, NoteCard, TimelineItem, Phone, TabBar, TopBar });
