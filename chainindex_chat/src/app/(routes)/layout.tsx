import { Nav } from '@chainindex/ui-custom';
import ChatList from '@/client/components/chat-list/ChatList';
import NavDrawerActions from '@/client/components/NavDrawerActions';
import NavActions from '@/client/components/NavActions';
import { NavTitle } from '@/client/components/NavTitle';

export default async function Chats({
  children, // will be a page or nested layout
  params,
}: {
  children: React.ReactNode;
  params: {
    chatId: string[];
  };
}) {
  const [chatId] = params.chatId ?? [];

  return (
    <section className="h-full overflow-y-hidden">
      <Nav
        drawerHeaderSlot={<NavDrawerActions />}
        drawerSlot={<ChatList chatId={chatId} />}
        actionSlot={<NavActions />}
        titleSlot={<NavTitle />}
      >
        <>{children}</>
      </Nav>
    </section>
  );
}
