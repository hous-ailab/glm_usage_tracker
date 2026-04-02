#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const CONFIG_FILE = path.join(__dirname, '.zai_apikey.json');
const BASE_URL = 'https://api.z.ai';

function formatDateTime(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  const h = String(date.getHours()).padStart(2, '0');
  const min = String(date.getMinutes()).padStart(2, '0');
  const s = String(date.getSeconds()).padStart(2, '0');
  return `${y}-${m}-${d} ${h}:${min}:${s}`;
}

async function fetchEndpoint(url, apiKey, label) {
  const authHeaders = [apiKey, `Bearer ${apiKey}`];
  for (const authHeader of authHeaders) {
    try {
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Authorization': authHeader,
          'Accept-Language': 'en-US,en',
          'Content-Type': 'application/json'
        }
      });
      if (response.status === 200) {
        const data = await response.json();
        return data.data || data;
      } else if (response.status === 401) {
        continue;
      } else {
        const errorText = await response.text();
        throw new Error(`[${label}] HTTP ${response.status}: ${errorText}`);
      }
    } catch (error) {
      if (error instanceof Error && !error.message.includes('401')) {
        throw error;
      }
      continue;
    }
  }
  throw new Error(`[${label}] Authentication failed with both token formats`);
}

async function fetchUsage(apiKey, planLimit) {
  if (!apiKey) {
    return { success: false, error: 'API key not configured' };
  }

  try {
    const now = new Date();
    const end = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
    const start7d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 7, 0, 0, 0, 0);
    const start30d = new Date(now.getFullYear(), now.getMonth() - 1, now.getDate(), 0, 0, 0, 0);

    const qp7d = `?startTime=${encodeURIComponent(formatDateTime(start7d))}&endTime=${encodeURIComponent(formatDateTime(end))}`;
    const qp30d = `?startTime=${encodeURIComponent(formatDateTime(start30d))}&endTime=${encodeURIComponent(formatDateTime(end))}`;

    const [quotaRes, usage7dRes, usage30dRes] = await Promise.allSettled([
      fetchEndpoint(`${BASE_URL}/api/monitor/usage/quota/limit`, apiKey, 'Quota limit'),
      fetchEndpoint(`${BASE_URL}/api/monitor/usage/model-usage${qp7d}`, apiKey, '7-day usage'),
      fetchEndpoint(`${BASE_URL}/api/monitor/usage/model-usage${qp30d}`, apiKey, '30-day usage')
    ]);

    let current5HourTokens = 0;
    let limit5HourTokens = 800000000;
    let percentage5Hour = 0;
    let resetTime = null;
    let sevenDayPrompts = 0;
    let sevenDayTokens = 0;
    let thirtyDayPrompts = 0;
    let thirtyDayTokens = 0;

    if (quotaRes.status === 'fulfilled' && quotaRes.value) {
      const quotaData = quotaRes.value;
      if (quotaData.limits) {
        for (const limit of quotaData.limits) {
          if (limit.type === 'TOKENS_LIMIT') {
            percentage5Hour = limit.percentage || 0;
            if (limit.currentValue !== undefined) current5HourTokens = limit.currentValue;
            if (limit.usage !== undefined) limit5HourTokens = limit.usage;
            if (limit.nextResetTime) resetTime = limit.nextResetTime;
            if (current5HourTokens === 0 && percentage5Hour > 0) {
              current5HourTokens = Math.floor(limit5HourTokens * percentage5Hour / 100);
            }
          }
        }
      }
    }

    if (usage7dRes.status === 'fulfilled' && usage7dRes.value) {
      const d = usage7dRes.value;
      if (d.totalUsage) {
        sevenDayPrompts = d.totalUsage.totalModelCallCount || 0;
        sevenDayTokens = d.totalUsage.totalTokensUsage || 0;
      }
    }

    if (usage30dRes.status === 'fulfilled' && usage30dRes.value) {
      const d = usage30dRes.value;
      if (d.totalUsage) {
        thirtyDayPrompts = d.totalUsage.totalModelCallCount || 0;
        thirtyDayTokens = d.totalUsage.totalTokensUsage || 0;
      }
    }

    return {
      success: true,
      data: {
        current5HourTokens, limit5HourTokens, percentage5Hour, resetTime,
        sevenDayPrompts, sevenDayTokens,
        thirtyDayPrompts, thirtyDayTokens,
        lastUpdated: new Date(),
        connectionStatus: 'connected'
      }
    };
  } catch (error) {
    return { success: false, error: error instanceof Error ? error.message : 'Unknown error' };
  }
}

async function debugFetch(apiKey) {
  const quotaData = await fetchEndpoint(`${BASE_URL}/api/monitor/usage/quota/limit`, apiKey, 'Quota limit');
  console.log('\n=== API 原始响应 ===');
  console.log(JSON.stringify(quotaData, null, 2));
  return quotaData;
}

function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_FILE)) {
      return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    }
  } catch (e) {
    console.error('Error loading config:', e);
  }
  return null;
}

function saveConfig(config) {
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
  console.log(`Config saved to: ${CONFIG_FILE}`);
}

function formatNumber(num) {
  if (num >= 1000000000) return (num / 1000000000).toFixed(2) + 'B';
  if (num >= 1000000) return (num / 1000000).toFixed(2) + 'M';
  if (num >= 1000) return (num / 1000).toFixed(2) + 'K';
  return num.toString();
}

function formatResetTime(resetTime) {
  if (!resetTime) return null;
  try {
    const date = new Date(resetTime);
    if (isNaN(date.getTime())) return null;
    return date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
  } catch {
    return null;
  }
}

function displayUsage(data) {
  console.log('\n╔═══════════════════════════════════════════════════════════╗');
  console.log('║                Z.ai GLM 用量统计                         ║');
  console.log('╚═══════════════════════════════════════════════════════════╝\n');

  console.log('📊 5小时滚动窗口配额 (Token):');
  console.log(`   已使用: ${formatNumber(data.current5HourTokens)} / ${formatNumber(data.limit5HourTokens)}`);
  console.log(`   使用率: ${data.percentage5Hour.toFixed(2)}%`);
  if (data.resetTime) {
    const resetStr = formatResetTime(data.resetTime);
    if (resetStr) console.log(`   重置时间: ${resetStr}`);
  }
  console.log('');
  console.log('📊 7天统计:');
  console.log(`   请求次数: ${formatNumber(data.sevenDayPrompts)}`);
  console.log(`   Token用量: ${formatNumber(data.sevenDayTokens)}`);
  console.log('');
  console.log('📊 30天统计:');
  console.log(`   请求次数: ${formatNumber(data.thirtyDayPrompts)}`);
  console.log(`   Token用量: ${formatNumber(data.thirtyDayTokens)}`);
  console.log('');
  console.log(`🕐 最后更新: ${data.lastUpdated.toLocaleString()}`);
  console.log(`🔗 连接状态: ${data.connectionStatus}\n`);
}

async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === 'help') {
    console.log('Z.ai GLM Usage Tracker CLI\n');
    console.log('用法:');
    console.log('  node zai-cli-js.js config <api-key>   配置 API Key');
    console.log('  node zai-cli-js.js check              查询用量统计');
    console.log('  node zai-cli-js.js debug              查看API原始响应\n');
    return;
  }

  const command = args[0];

  if (command === 'config') {
    if (args.length < 2) {
      console.error('错误: 请提供 API Key');
      process.exit(1);
    }
    saveConfig({ apiKey: args[1] });
    return;
  }

  if (command === 'check') {
    const config = loadConfig();
    if (!config?.apiKey) {
      console.error('错误: 请先配置 API Key');
      console.log('用法: node index.js config <api-key>');
      process.exit(1);
    }
    console.log('正在查询用量统计...');
    const result = await fetchUsage(config.apiKey, config.planLimit || 800000000);
    if (result.success && result.data) {
      displayUsage(result.data);
    } else {
      console.error('错误:', result.error);
      process.exit(1);
    }
    return;
  }

  if (command === 'debug') {
    const config = loadConfig();
    if (!config?.apiKey) {
      console.error('错误: 请先配置 API Key');
      process.exit(1);
    }
    await debugFetch(config.apiKey);
    return;
  }

  console.error('未知命令:', command);
  process.exit(1);
}

if (require.main === module) {
  main().catch((e) => { console.error('发生错误:', e); process.exit(1); });
}

module.exports = {
  fetchUsage,
  loadConfig,
  saveConfig,
  displayUsage
};
