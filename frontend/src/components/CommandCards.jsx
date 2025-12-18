import React from 'react';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { SortableCommandCard } from './SortableCommandCard';
import ReleaseManagerCard from './ReleaseManagerCard';
import SystemCommandCard from './SystemCommandCard';
import { RefreshCw } from 'lucide-react';
import { isReleaseManagerCard, isSystemCard } from '../utils/defaultCommandCards';

const CommandCards = ({ commands, loading, error, onExecute, onPaste, onEdit, onDelete, onRetry, onToast }) => {
  if (loading) {
    return (
      <div className="command-cards-container">
        <div className="command-cards-loading">
          <div className="spinner"></div>
          <p>Loading command cards...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="command-cards-container">
        <div className="command-cards-error">
          <p className="error-message">⚠️ Failed to load command cards</p>
          <p className="error-details">{error}</p>
          {onRetry && (
            <button className="btn btn-primary" onClick={onRetry}>
              <RefreshCw size={16} />
              Retry
            </button>
          )}
        </div>
      </div>
    );
  }

  if (commands.length === 0) {
    return (
      <div className="command-cards-container">
        <div className="command-cards-empty">
          <p>No command cards yet. Click the + button to add one.</p>
        </div>
      </div>
    );
  }

  // Separate system cards from user cards
  const systemCards = commands.filter(isSystemCard);
  const userCards = commands.filter(cmd => !isSystemCard(cmd));

  return (
    <div className="command-cards-container">
      {/* System Cards Section */}
      {systemCards.length > 0 && (
        <div className="system-cards-section">
          <div className="system-cards-divider">
            <span>System Cards</span>
          </div>
          {systemCards.map(cmd => {
            if (isReleaseManagerCard(cmd)) {
              return (
                <ReleaseManagerCard
                  key={cmd.id}
                  onExecuteCommand={onExecute}
                  onToast={onToast}
                />
              );
            }
            // Render other system cards using SystemCommandCard
            return (
              <SystemCommandCard
                key={cmd.id}
                card={cmd}
                onExecuteCommand={onExecute}
                onToast={onToast}
                onConfigureCard={onEdit}
              />
            );
          })}
        </div>
      )}

      {/* User Cards Section */}
      {userCards.length > 0 && (
        <>
          {systemCards.length > 0 && (
            <div className="user-cards-divider">
              <span>Your Command Cards</span>
            </div>
          )}
          <SortableContext
            items={userCards.map(c => c.id)}
            strategy={verticalListSortingStrategy}
          >
            {userCards.map(cmd => (
              <SortableCommandCard
                key={cmd.id}
                command={cmd}
                onExecute={onExecute}
                onPaste={onPaste}
                onEdit={onEdit}
                onDelete={onDelete}
              />
            ))}
          </SortableContext>
        </>
      )}

      {/* Empty State */}
      {systemCards.length === 0 && userCards.length === 0 && (
        <div className="command-cards-empty">
          <p>No command cards yet. Click the + button to add one.</p>
        </div>
      )}
    </div>
  );
};

export default CommandCards;
