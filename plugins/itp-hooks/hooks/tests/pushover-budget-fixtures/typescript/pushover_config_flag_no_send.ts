interface NotificationConfig {
  pushover_enabled: boolean;
  pushover_device: string;
  email_enabled: boolean;
  slack_enabled: boolean;
}

const config: NotificationConfig = {
  pushover_enabled: true,
  pushover_device: 'iphone',
  email_enabled: false,
  slack_enabled: true,
};

if (config.pushover_enabled) {
  console.log('Pushover notifications are enabled in config');
}
