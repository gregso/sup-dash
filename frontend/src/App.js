import React from 'react';

function App() {
  return (
    <div className="App" style={{ padding: '20px', maxWidth: '1200px', margin: '0 auto' }}>
      <header style={{ marginBottom: '30px', borderBottom: '1px solid #eaeaea', paddingBottom: '20px' }}>
        <h1 style={{ color: '#333' }}>Task Monitoring Dashboard</h1>
        <p style={{ color: '#666' }}>Track and manage tasks across your organization</p>
      </header>

      <main>
        <section style={{ marginBottom: '30px', padding: '20px', backgroundColor: '#f5f5f5', borderRadius: '8px' }}>
          <h2 style={{ marginBottom: '15px', color: '#444' }}>Welcome!</h2>
          <p>This is a placeholder for the Task Monitoring Dashboard. The real application will include:</p>
          <ul style={{ marginTop: '10px', marginLeft: '20px' }}>
            <li>Task overview and statistics</li>
            <li>Live issue tracking</li>
            <li>Task action monitoring</li>
            <li>Department performance metrics</li>
            <li>AI-powered task summarization</li>
          </ul>
        </section>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: '20px' }}>
          <div style={{ padding: '20px', backgroundColor: '#e6f7ff', borderRadius: '8px', boxShadow: '0 2px 4px rgba(0,0,0,0.1)' }}>
            <h3 style={{ marginBottom: '10px', color: '#0066cc' }}>Task Statistics</h3>
            <p>Visualize task metrics and performance indicators</p>
          </div>

          <div style={{ padding: '20px', backgroundColor: '#fff1f0', borderRadius: '8px', boxShadow: '0 2px 4px rgba(0,0,0,0.1)' }}>
            <h3 style={{ marginBottom: '10px', color: '#cf1322' }}>Live Issues</h3>
            <p>Monitor high-priority tasks requiring immediate attention</p>
          </div>

          <div style={{ padding: '20px', backgroundColor: '#f6ffed', borderRadius: '8px', boxShadow: '0 2px 4px rgba(0,0,0,0.1)' }}>
            <h3 style={{ marginBottom: '10px', color: '#389e0d' }}>Department Analytics</h3>
            <p>Track performance across different departments</p>
          </div>
        </div>
      </main>

      <footer style={{ marginTop: '40px', textAlign: 'center', color: '#999', fontSize: '14px', paddingTop: '20px', borderTop: '1px solid #eaeaea' }}>
        <p>Task Monitoring System &copy; 2025</p>
      </footer>
    </div>
  );
}

export default App;
