const CalendarView = () => {
  // 5 weeks, today = April 23 (Thursday)
  // Day-of-month grid. First row starts on a Sunday.
  // April 2026: 1st = Wednesday. Simplified to a plausible layout.
  const days = [];
  for (let i = -2; i <= 32; i++) {
    const dayNum = i;
    const other = dayNum < 1 || dayNum > 30;
    const today = dayNum === 23;
    // Seed colored dots deterministically
    const dots = [];
    if (!other) {
      const seed = dayNum;
      if (seed % 2 === 0) dots.push("var(--dc-workout)");  // workout — clay
      if (seed % 3 === 0) dots.push("var(--dc-meal)");     // meal — turmeric
      if (seed % 4 === 0) dots.push("var(--dc-sleep)");    // sleep — dusk
      if (seed % 5 === 0) dots.push("var(--dc-mood)");     // mood — plum
      if (seed % 7 === 0) dots.push("var(--dc-activity)"); // activity — moss
    }
    days.push({ dayNum, other, today, dots });
  }

  const dow = ["S","M","T","W","T","F","S"];

  return (
    <>
      <TopBar sub="April 2026" title="Your month"
        left={<button className="iconbtn"><Icon name="chevron-left" /></button>}
        right={<button className="iconbtn"><Icon name="chevron-right" /></button>} />
      <div className="content">
        <div className="cal">
          {dow.map((d,i) => <div key={i} className="dow">{d}</div>)}
          {days.slice(0, 35).map((d, i) => (
            <div key={i} className={"cell" + (d.other ? " other" : "") + (d.today ? " today" : "")}>
              <span>{d.other ? "" : d.dayNum}</span>
              {!d.other && <div className="dots">{d.dots.slice(0,4).map((c,j) => <span key={j} style={{background:c}} />)}</div>}
            </div>
          ))}
        </div>

        <div className="section-label">Today · 6 notes</div>
        <div style={{display:"flex", flexDirection:"column", gap:10}}>
          <NoteCard type="workout" time="7:12 am" title="Easy run · 35 min" />
          <NoteCard type="meal" time="8:30 am" title="Oatmeal, berries" />
          <NoteCard type="mood" time="10:05 am" title="Focused" />
        </div>
      </div>
    </>
  );
};

window.CalendarView = CalendarView;
