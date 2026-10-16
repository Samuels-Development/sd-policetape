// The switches of shared/settings.lua, by group, each with what it does. They change the config
// for everyone at once and are kept in data/settings.json; one that differs from the config file
// says so. A switch that only matters while another is on dims while that one is off.
import { useT } from '../locale';
import { act } from './api';
import { ScrollArea } from './ScrollArea';
import { Badge, Heading, Hint, Switch } from './shared';
import { useAdmin } from './store';

const GROUPS = ['tape', 'holders', 'placing', 'saving', 'item'];

// What each depends on: without it, it has nothing to do.
const NEEDS: Record<string, string> = {
  PersistChoice: 'Persist',
  'Holders.Vehicles': 'Holders.Knock',
  'Holders.Kick': 'Holders.Knock',
  'Holders.Run': 'Holders.Knock',
  'Holders.StandUp': 'Holders.Knock',
  'Item.Consume': 'Item.Enabled',
  'Item.Refund': 'Item.Consume',
};

const words = (key: string) => `admin.settings.toggles.${key.replace('.', '_')}`;

export function SettingsTab() {
  const t = useT();
  const snapshot = useAdmin((s) => s.snapshot)!;
  const busy = useAdmin((s) => s.busy);
  const value = new Map(snapshot.toggles.map((tg) => [tg.key, tg.on]));
  const live = (key: string): boolean => {
    const need = NEEDS[key];
    return !need || (value.get(need) === true && live(need));
  };

  return (
    <ScrollArea className="h-full" viewClassName="flex flex-col gap-4 px-6 py-5">
      <Heading title={t('admin.settings.title')} />
      <Hint className="-mt-2">{t('admin.settings.hint')}</Hint>

      {GROUPS.map((g) => {
        const rows = snapshot.toggles.filter((tg) => tg.group === g);
        if (rows.length === 0) return null;
        return (
          <section key={g} className="flex flex-shrink-0 flex-col gap-2">
            <span className="sc-label px-1">{t(`admin.settings.groups.${g}`)}</span>
            <div className="sc-card overflow-hidden">
              {rows.map((tg, i) => {
                const label = t(`${words(tg.key)}.label`);
                const changed = tg.on !== tg.default;
                return (
                  <div
                    key={tg.key}
                    className="flex items-center gap-5 px-5 py-4 transition-opacity"
                    style={{ borderTop: i ? '1px solid var(--hairline)' : 'none', opacity: live(tg.key) ? 1 : 0.5 }}
                  >
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span className="text-[13.5px] font-semibold">{label}</span>
                        {changed && (
                          <Badge tone="warn" title={t('admin.common.changed_hint', { value: t(tg.default ? 'admin.common.on' : 'admin.common.off').toLowerCase() })}>
                            {t('admin.common.changed')}
                          </Badge>
                        )}
                      </div>
                      <Hint className="mt-1">{t(`${words(tg.key)}.hint`)}</Hint>
                    </div>
                    <span className="mono text-[11px]" style={{ color: 'var(--text-4)' }}>
                      {tg.key}
                    </span>
                    <Switch
                      on={tg.on}
                      label={label}
                      disabled={busy}
                      onChange={(on) => void act('toggle', { key: tg.key, on }, t(on ? 'admin.settings.toast_on' : 'admin.settings.toast_off', { name: label }))}
                    />
                  </div>
                );
              })}
            </div>
          </section>
        );
      })}
    </ScrollArea>
  );
}
