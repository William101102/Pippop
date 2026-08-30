import type { CSSProperties } from 'react';
import type { Profile } from '../types';

type AvatarProps = {
  profile: Pick<Profile, 'display_name' | 'avatar_color' | 'avatar_url' | 'status_emoji'>;
  className?: string;
  showStatus?: boolean;
};

export function Avatar({ profile, className = '', showStatus = false }: AvatarProps) {
  const style = { '--avatar-color': profile.avatar_color } as CSSProperties;
  return (
    <span className={`avatar-photo ${className}`} style={style}>
      {profile.avatar_url ? (
        <img src={profile.avatar_url} alt={`${profile.display_name}的头像`} referrerPolicy="no-referrer" />
      ) : (
        <span>{profile.display_name.trim().slice(0, 1).toUpperCase()}</span>
      )}
      {showStatus && <i>{profile.status_emoji}</i>}
    </span>
  );
}
