import { useEffect, useState } from 'react'
import axios from 'axios'
import { Line } from 'react-chartjs-2'
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  TimeScale,
} from 'chart.js'
ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, TimeScale)

export default function HomePage() {
  const [running, setRunning] = useState(false)
  const [prices, setPrices] = useState<number[]>([])
  const [labels, setLabels] = useState<string[]>([])
  const [logs, setLogs] = useState<string[]>("")

  const fetchStatus = async () => {
    const res = await axios.get('/status')
    setRunning(res.data.running)
  }

  const fetchLogs = async () => {
    const res = await axios.get('/logs')
    setLogs(res.data.logs.join('\n'))
  }

  const fetchChart = async () => {
    const res = await axios.get('/chart-data')
    setPrices(res.data.prices)
    setLabels(res.data.timestamps)
  }

  const startBot = async () => {
    await axios.post('/start')
    fetchStatus()
  }
  const stopBot = async () => {
    await axios.post('/stop')
    fetchStatus()
  }

  useEffect(() => {
    fetchStatus()
    const interval = setInterval(() => {
      fetchLogs()
      fetchChart()
      fetchStatus()
    }, 2000)
    return () => clearInterval(interval)
  }, [])

  const data = {
    labels,
    datasets: [{
      label: 'Price',
      data: prices,
      borderColor: 'rgb(75, 192, 192)',
      tension: 0.1,
    }]
  }

  return (
    <div style={{ padding: 20 }}>
      <h1>Trading Bot</h1>
      <div>
        <button onClick={startBot} disabled={running}>Start Bot</button>
        <button onClick={stopBot} disabled={!running}>Stop Bot</button>
      </div>
      <h2>Status: {running ? 'Running' : 'Stopped'}</h2>
      <div style={{ width: '600px', height: '300px' }}>
        <Line data={data} />
      </div>
      <pre style={{ background: '#111', color: '#0f0', padding: '10px' }}>{logs}</pre>
    </div>
  )
}
