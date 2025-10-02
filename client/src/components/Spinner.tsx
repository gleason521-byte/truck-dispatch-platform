import React from 'react';

export default function Spinner() {
  return (
    <div style={{ textAlign: 'center', marginTop: '2rem' }}>
      <div className="spinner" />
      <p>Loading...</p>
    </div>
  );
}
