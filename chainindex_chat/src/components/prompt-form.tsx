import { Send } from 'lucide-react';
import { Button } from './ui/button'; // Adjust import based on your setup
import { Textarea } from './ui/textarea'; // Adjust import based on your setup

function PromptForm({ prompt, setPrompt, handleSubmit, currentQuery }) {
  return (
    <form onSubmit={handleSubmit} className="p-4">
      <div className="relative flex-1">
        <Textarea
          value={prompt}
          onChange={(e) => {
            setPrompt(e.target.value);
            e.target.style.height = 'auto';
            e.target.style.height = `${e.target.scrollHeight}px`;
          }}
          placeholder="Describe your query..."
          disabled={currentQuery?.isGenerating}
          className="w-full min-h-[40px] pr-10 pb-10 resize-none overflow-hidden border-2 hover:border-primary/50 focus-visible:ring-0 focus-visible:ring-offset-0 focus-visible:border-primary transition-colors"
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault();
              handleSubmit(e);
            }
          }}
          style={{
            height: '40px',
            minHeight: '40px',
            maxHeight: '200px',
          }}
        />
        <Button
          type="submit"
          disabled={currentQuery?.isGenerating || !prompt.trim()}
          className="absolute right-2 bottom-2 shrink-0 transition-colors hover:bg-primary/90"
        >
          <Send className="h-4 w-4" />
          <span className="sr-only">Submit</span>
        </Button>
      </div>
    </form>
  );
}

export default PromptForm;
