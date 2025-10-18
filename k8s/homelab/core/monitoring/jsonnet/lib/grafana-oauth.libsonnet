{
  values+: {
    grafana+: {
      config+: {
        sections+: {
          auth: {
            signout_redirect_url: 'https://auth.liquid.sh/application/o/grafana/end-session/',
            oauth_auto_login: true,
          },
          'auth.generic_oauth': {
            name: 'auth.liquid.sh',
            enabled: true,
            client_id: '$__file{/etc/secrets/auth_generic_oauth/client_id}',
            client_secret: '$__file{/etc/secrets/auth_generic_oauth/client_secret}',
            scopes: 'openid email profile',
            auth_url: 'https://auth.liquid.sh/application/o/authorize/',
            token_url: 'https://auth.liquid.sh/application/o/token/',
            api_url: 'https://auth.liquid.sh/application/o/userinfo/',
            role_attribute_path: "contains(groups, 'K8s Cluster Admins') && 'Admin'",
          },
        },
      },
    },
  },

  grafana+: {
    oauthClientSecret: (import 'grafana-oauth/oauth-client-secret.json'),
  },
}
