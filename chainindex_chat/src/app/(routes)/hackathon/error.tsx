'use client';

import { Button, NavigationItem } from '@chainindex/ui-custom';

export default function Error() {
  return (
    <div className="flex p-0 w-full h-screen mt-7">
      <div className="flex flex-col w-full max-h-[90vh] items-center justify-center">
        <div className="px-0 overflow-scroll">
          <h6>Something went wrong!</h6>
        </div>
        <div className="px-0 overflow-scroll">
          <Button
            theme="icon"
            size="small"
            onClick={() => (window.location.href = '/chats')}
          >
            <NavigationItem>Try again</NavigationItem>
          </Button>
        </div>
      </div>
    </div>
  );
}
