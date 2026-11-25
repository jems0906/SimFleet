import { useEffect, useState } from "react";
import VersionCompare from "./components/VersionCompare.jsx";
import ScenarioDetail from "./components/ScenarioDetail.jsx";
import FlakyList from "./components/FlakyList.jsx";
import BatchHealth from "./components/BatchHealth.jsx";
import { fetchJson } from "./api.js";

export default function App() {
  const [data, setData] = useState({ passRates: [], regressions: [], flaky: [], batches: [] });
  const [window, setWindow] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    Promise.all([
      fetchJson("/api/analytics/pass-rates"),
      fetchJson("/api/analytics/regressions?baseline=v1&candidate=v2"),
      fetchJson("/api/analytics/flaky?version=v1"),
      fetchJson("/api/batches")
    ]).then(([pass, regressions, flaky, batches]) => {
      setData({ passRates: pass.results, regressions: regressions.results, flaky: flaky.results, batches });
      setWindow(pass.window);
    }).catch(() => setError("Dashboard data is unavailable. Please try again later."));
  }, []);

  return (
    <main>
      <header><div><p className="eyebrow">SIMULATION OPERATIONS</p><h1>SimFleet</h1></div><span className="window">{window?.start?.slice(0, 10) || (error ? "Unavailable" : "Loading")}</span></header>
      {error && <p role="alert">{error}</p>}
      <section className="grid"><VersionCompare rows={data.passRates} regressions={data.regressions} /><ScenarioDetail /></section>
      <section className="grid"><FlakyList rows={data.flaky} /><BatchHealth rows={data.batches} /></section>
    </main>
  );
}
