import { LoaderCircular } from '@chainindex/ui-custom';

import React from 'react';

export default function Loading() {
  return (
    <div className="flex justify-center items-center h-screen">
      <LoaderCircular />
    </div>
  );
}
