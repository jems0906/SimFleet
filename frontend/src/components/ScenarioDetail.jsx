import { useEffect, useState } from "react";

export default function ScenarioDetail() {
  const [data, setData] = useState(null);
  const [worst, setWorst] = useState([]);
  const [failures, setFailures] = useState([]);
  useEffect(() => {
    const api = import.meta.env.VITE_API_URL || "";
    Promise.all([
      fetch(`${api}/api/analytics/distributions?version=v1&metric=comfort_jerk`).then(r => r.json()),
      fetch(`${api}/api/analytics/worst-trajectories?version=v1&metric=comfort_jerk&limit=3`).then(r => r.json()),
      fetch(`${api}/api/analytics/failures`).then(r => r.json())
    ]).then(([distribution, worstData, failureData]) => {
      setData(distribution);
      setWorst(worstData.results || []);
      setFailures(failureData.results || []);
    }).catch(() => setData(null));
  }, []);

  const row = data?.results?.[0];
  return <article className="panel"><h2>Scenario detail</h2>
    <div className="metrics">
      <div className="metric"><strong>{row ? row.median.toFixed(2) : "-"}</strong><span>median comfort jerk</span></div>
      <div className="metric"><strong>{row ? row.p95.toFixed(2) : "-"}</strong><span>p95 comfort jerk</span></div>
      <div className="metric"><strong>{data?.run_count ?? "-"}</strong><span>runs in window</span></div>
    </div>
    {worst.length > 0 && <p>Worst trajectories: {worst.map(item => `${item.name} (${item.metric_value.toFixed(2)})`).join(", ")}</p>}
    {failures.length > 0 && <p>Failure reasons: {failures.map(item => `${item.driver_version}: ${item.failure_category} (${item.failure_count})`).join(", ")}</p>}
  </article>;
}
