import { useEffect, useState } from "react";
import VersionCompare from "./components/VersionCompare.jsx";
import ScenarioDetail from "./components/ScenarioDetail.jsx";
import FlakyList from "./components/FlakyList.jsx";
import BatchHealth from "./components/BatchHealth.jsx";

const api = import.meta.env.VITE_API_URL || "http://localhost:8000";

export default function App() {
  const [data, setData] = useState({ passRates: [], regressions: [], flaky: [], batches: [] });
  const [window, setWindow] = useState(null);

  useEffect(() => {
    Promise.all([
      fetch(`${api}/api/analytics/pass-rates`).then(r => r.json()),
      fetch(`${api}/api/analytics/regressions?baseline=v1&candidate=v2`).then(r => r.json()),
      fetch(`${api}/api/analytics/flaky?version=v1`).then(r => r.json()),
      fetch(`${api}/api/batches`).then(r => r.json())
    ]).then(([pass, regressions, flaky, batches]) => {
      setData({ passRates: pass.results, regressions: regressions.results, flaky: flaky.results, batches });
      setWindow(pass.window);
    }).catch(() => setWindow({ start: "Database unavailable", end: "" }));
  }, []);

  return (
    <main>
      <header><div><p class="eyebrow">SIMULATION OPERATIONS</p><h1>SimFleet</h1></div><span class="window">{window?.start?.slice(0, 10) || "Loading"}</span></header>
      <section class="grid"><VersionCompare rows={data.passRates} regressions={data.regressions} /><ScenarioDetail /></section>
      <section class="grid"><FlakyList rows={data.flaky} /><BatchHealth rows={data.batches} /></section>
    </main>
  );
}
