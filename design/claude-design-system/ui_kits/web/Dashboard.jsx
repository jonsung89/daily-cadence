const Dashboard = () => {
  const timeline = [
    { t: "6:45 am", type: "sleep", title: "Slept 7h 20m", body: "Solid. Woke up once around 3am." },
    { t: "7:12 am", type: "workout", title: "Easy run · 35 min", body: "Felt strong." },
    { t: "8:30 am", type: "meal", title: "Breakfast", body: "Oatmeal, berries, coffee." },
    { t: "10:05 am",type: "mood", title: "Focused", body: "Clear head." },
    { t: "12:40 pm",type: "meal", title: "Lunch", body: "Grain bowl, salmon." },
    { t: "3:15 pm", type: "activity", title: "Walk · 2.3 mi", body: "Park loop." },
  ];
  const sleepData = [6.2, 6.8, 7.1, 6.5, 7.4, 8.0, 7.2, 6.9, 7.6, 7.0, 6.8, 7.5, 7.8, 7.3];

  const StatCard = ({ label, num, unit, delta, note }) => (
    <div className="card">
      <div className="stat-row">
        <h3 className="stat-label">{label}</h3>
        {delta && <span className="delta">{delta}</span>}
      </div>
      <div className="stat-big"><span className="num">{num}</span>{unit && <span className="unit">{unit}</span>}</div>
      <div className="stat-note">{note}</div>
    </div>
  );

  return (
    <main className="main">
      <div className="topnav">
        <div>
          <div className="eyebrow">Thursday · April 23</div>
          <h1>Good morning, Sam</h1>
        </div>
        <div className="actions">
          <button className="btn secondary"><Icn name="share-2" /> Share</button>
          <button className="btn primary"><Icn name="plus" /> New note</button>
        </div>
      </div>

      <div className="grid" style={{gridTemplateColumns: "repeat(4, 1fr)"}}>
        <StatCard label="Sleep" num="7h 20m" delta="+12m" note="Woke 6:45 am" />
        <StatCard label="Weight" num="168.2" unit="lbs" delta="−1.4" note="Down from 169.6" />
        <StatCard label="Workouts" num="3" unit="this week" note="On pace for 4" />
        <StatCard label="Steps" num="6,240" unit="of 8k" note="78% of daily goal" />
      </div>

      <div className="grid" style={{gridTemplateColumns: "2fr 1fr", marginTop: 20}}>
        <div className="card">
          <div className="stat-row"><h3 className="stat-label">Today's timeline</h3><span className="sub">6 notes</span></div>
          <div className="tlist">
            {timeline.map((n, i) => {
              const c = TYPE_COLORS_W[n.type];
              return (
                <div key={i} className="row">
                  <span className="t">{n.t}</span>
                  <div className="content">
                    <span className="dot" style={{background: c.dot}}></span>
                    <span className="title">{n.title}</span>
                    <span className="body">{n.body}</span>
                  </div>
                  <span className="type">{c.label}</span>
                </div>
              );
            })}
          </div>
        </div>
        <div className="card">
          <div className="stat-row"><h3 className="stat-label">Sleep · 14 days</h3><span className="sub">avg 7h 12m</span></div>
          <LineChart data={sleepData} height={220} />
        </div>
      </div>
    </main>
  );
};

window.Dashboard = Dashboard;
