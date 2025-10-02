import React from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from './lib/useAuth';
import Spinner from './components/Spinner';

export default function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth();

  if (loading) return <Spinner />;

  return user ? children : <Navigate to="/login" />;
}
