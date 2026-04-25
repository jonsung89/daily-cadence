const Dashboard = () => {
  return (
    <>
      <TopBar sub="Good morning, Sam" title="Today at a glance"
        right={<button className="iconbtn"><Icon name="settings" /></button>} />
      <div className="content">
        <div className="wgrid">
          <div className="w" style={{background:"var(--dc-sleep)", color:"var(--fg-on-accent)", border:"0"}}>
            <div className="lbl" style={{color:"var(--dc-sleep-soft)"}}>Sleep</div>
            <div className="big" style={{color:"var(--fg-on-accent)"}}>7h 20m</div>
            <div className="sub" style={{color:"var(--dc-sleep-soft)"}}>woke 6:45 am</div>
          </div>
          <div className="w" style={{background:"var(--dc-workout-soft)", border:"0"}}>
            <div className="lbl" style={{color:"var(--dc-workout)"}}>Workouts</div>
            <div className="big">3</div>
            <div className="sub">this week</div>
          </div>
          <div className="w wide" style={{background:"var(--bg-2)"}}>
            <div style={{display:"flex", justifyContent:"space-between", alignItems:"center"}}>
              <div>
                <div className="lbl">Weight</div>
                <div style={{display:"flex", alignItems:"baseline", gap:8, marginTop:4}}>
                  <span className="big">168.2</span>
                  <span style={{fontSize:12, color:"var(--fg-2)"}}>lbs</span>
                  <span style={{fontSize:11, color:"var(--dc-sage-deep)", fontWeight:600, background:"var(--dc-sage-soft)", padding:"2px 8px", borderRadius:999, marginLeft:6}}>−1.4</span>
                </div>
              </div>
              <svg width="110" height="50" viewBox="0 0 110 50">
                <path d="M2,28 L15,26 L28,30 L41,24 L54,22 L67,20 L80,18 L93,14 L108,10"
                  fill="none" stroke="var(--dc-sage)" strokeWidth="2" strokeLinecap="round" />
                <circle cx="108" cy="10" r="3" fill="var(--dc-sage)" />
              </svg>
            </div>
          </div>
          <div className="w" style={{background:"var(--dc-meal-soft)", border:"0"}}>
            <div className="lbl" style={{color:"var(--dc-meal)"}}>Meals</div>
            <div className="big">2</div>
            <div className="sub">logged today</div>
          </div>
          <div className="w" style={{background:"var(--dc-activity-soft)", border:"0"}}>
            <div className="lbl" style={{color:"var(--dc-activity)"}}>Steps</div>
            <div className="big">6,240</div>
            <div className="sub">of 8,000</div>
          </div>
          <div className="w wide">
            <div className="lbl" style={{color:"var(--dc-mood)"}}>This week's mood</div>
            <div style={{display:"flex", gap:6, marginTop:12, alignItems:"flex-end", height:40}}>
              {[0.5, 0.7, 0.6, 0.9, 0.75, 0.85, 0.8].map((h,i) => (
                <div key={i} style={{flex:1, height: `${h*100}%`, background:"var(--dc-mood)", borderRadius:4, opacity: 0.6 + h*0.4}}></div>
              ))}
            </div>
            <div style={{display:"flex", justifyContent:"space-between", marginTop:6, fontFamily:"var(--font-mono)", fontSize:9, color:"var(--fg-2)"}}>
              <span>M</span><span>T</span><span>W</span><span>T</span><span>F</span><span>S</span><span>S</span>
            </div>
          </div>
        </div>
      </div>
    </>
  );
};

window.Dashboard = Dashboard;
