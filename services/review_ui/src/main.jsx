import React from "react"
import { createRoot } from "react-dom/client"

function App(){
  const [jobs, setJobs] = React.useState([])
  React.useEffect(()=>{
    fetch("/api/v1/jobs/00000000-0000-0000-0000-000000000000").catch(()=>{}) // placeholder
  },[])
  return (<div style={{fontFamily:"Inter, system-ui"}}>
    <h1>AI Redaction Suite — Review UI (MVP)</h1>
    <p>Hook this to /api for real data. For now, it's a placeholder. </p>
  </div>)
}

createRoot(document.getElementById("root")).render(<App/>)
