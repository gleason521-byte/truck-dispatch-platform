import React from 'react';
import { Routes, Route, Link } from 'react-router-dom';
import Login from './Login';
import Signup from './Signup'; // no .tsx
import Dashboard from './Dashboard';
import ProtectedRoute from './ProtectedRoute';
export default function App() {
  return (
    <div>
      <h1>🚚 Dispatch Platform</h1>
      <nav>
        <Link to="/login">Login</Link> | <Link to="/signup">Signup</Link> | <Link to="/dashboard">Dashboard</Link>
      </nav>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/signup" element={<Signup />} />
        <Route
          path="/dashboard"
          element={
            <ProtectedRoute>
              <Dashboard />
            </ProtectedRoute>
          }
        />
        <Route path="*" element={<Login />} />
      </Routes>
    </div>
  );
}
// Trigger Firebase deploy
