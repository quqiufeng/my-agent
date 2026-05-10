#!/usr/bin/env python3
"""
天气查询任务 - 查询城市一周内的天气情况
依赖：无（使用 wttr.in 免费天气服务）
"""
import sys
import os
import re
import json
import requests

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tasks.base import BaseTask, TaskResult
from logger import task_logger as logger


class WeatherTask(BaseTask):
    """天气查询任务"""
    task_type = "weather"
    
    def __init__(self):
        self.base_url = "https://wttr.in"
    
    def execute(self, content: dict, session_webhook=None) -> dict:
        # 兼容处理：支持 raw 参数或 city 参数
        raw = content.get("raw", "")
        city = raw.replace("#weather", "").strip()
        
        if not city:
            return TaskResult.err("请提供城市名称，如: #weather 北京").to_dict()
        
        try:
            weather_info = self._get_weather(city)
            return TaskResult(success=True, stdout=weather_info).to_dict()
        except Exception as e:
            logger.error(f"天气查询失败: {e}")
            return TaskResult.err(f"天气查询失败: {str(e)}").to_dict()
    
    def _get_weather(self, city: str) -> str:
        """
        获取城市天气信息
        
        Args:
            city: 城市名称
            
        Returns:
            str: 格式化后的天气信息
        """
        # 使用 wttr.in 获取天气（支持中文）
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        
        # 尝试获取 3 天天气数据
        url = f"{self.base_url}/{city}?lang=zh&format=j1"
        
        try:
            response = requests.get(url, headers=headers, timeout=20)
            response.raise_for_status()
            data = response.json()
            
            return self._parse_weather_data(data, city)
        except requests.exceptions.RequestException as e:
            # 如果 API 调用失败，尝试简化模式
            return self._get_weather_simple(city)
    
    def _parse_weather_data(self, data: dict, city: str) -> str:
        """解析天气数据"""
        try:
            current = data.get("current_condition", [{}])[0]
            weather_desc = current.get("weatherDesc", [{}])[0].get("value", "未知")
            temp_C = current.get("temp_C", "0")
            feelsLikeC = current.get("FeelsLikeC", "0")
            humidity = current.get("humidity", "0")
            wind_km = current.get("windspeedKmph", "0")
            visibility = current.get("visibility", "0")
            uv_index = current.get("uvIndex", "0")
            
            # 获取今天和未来几天的天气
            weather = [f"🌍 {city} 当前天气"]
            weather.append(f"=" * 30)
            weather.append(f"🌡️ 温度: {temp_C}°C (体感 {feelsLikeC}°C)")
            weather.append(f"🌤️ 天气: {weather_desc}")
            weather.append(f"💧 湿度: {humidity}%")
            weather.append(f"🌬️ 风速: {wind_km} km/h")
            weather.append(f"👁️ 能见度: {visibility} km")
            weather.append(f"☀️ 紫外线指数: {uv_index}")
            
            # 添加未来几天预报
            weather.append("\n📅 未来天气预报:")
            weather.append("-" * 30)
            
            daily = data.get("weather", [])
            for i, day in enumerate(daily[:7]):  # 今天+未来6天（一周）
                date = day.get("date", "")
                if i == 0:
                    date = "今天"
                elif i == 1:
                    date = "明天"
                else:
                    # 转换日期格式
                    try:
                        from datetime import datetime
                        d = datetime.strptime(date, "%Y-%m-%d")
                        date = f"{d.month}/{d.day}"
                    except:
                        pass
                
                # 获取白天和夜间天气
                hourly = day.get("hourly", [])
                day_weather = hourly[4] if len(hourly) > 4 else {}  # 中午
                night_weather = hourly[-1] if hourly else {}  # 晚上
                
                day_desc = day_weather.get("weatherDesc", [{}])[0].get("value", "")
                night_desc = night_weather.get("weatherDesc", [{}])[0].get("value", "")
                
                day_temp = day_weather.get("tempC", "0")
                night_temp = night_weather.get("tempC", "0")
                
                chance_of_rain = day_weather.get("chanceofrain", "0")
                
                weather.append(f"\n【{date}】")
                weather.append(f"  🌤️ 白天: {day_desc} {day_temp}°C")
                weather.append(f"  🌙 夜间: {night_desc} {night_temp}°C")
                weather.append(f"  🌧️ 降雨概率: {chance_of_rain}%")
            
            return "\n".join(weather)
            
        except Exception as e:
            logger.error(f"解析天气数据失败: {e}")
            return self._get_weather_simple(city)
    
    def _get_weather_simple(self, city: str) -> str:
        """简化的天气查询（使用文本格式）"""
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        
        try:
            # 使用纯文本格式
            url = f"{self.base_url}/{city}?lang=zh"
            response = requests.get(url, headers=headers, timeout=10)
            response.raise_for_status()
            
            # 解析文本格式的天气
            text = response.text
            
            # 提取关键信息
            lines = text.split('\n')
            result = [f"🌍 {city} 天气预报"]
            result.append("=" * 30)
            
            # 找到天气信息部分
            found_weather = False
            for line in lines:
                # 跳过 ANSI 转义码和空行
                clean_line = re.sub(r'\x1b\[[0-9;]*m', '', line).strip()
                if not clean_line:
                    continue
                
                # 找到当前天气行
                if '°C' in clean_line and '↑' in clean_line:
                    found_weather = True
                    # 清理格式
                    clean_line = re.sub(r'\s+', ' ', clean_line)
                    result.append(f"🌡️ {clean_line}")
                elif found_weather and clean_line:
                    result.append(clean_line)
                    if len(result) > 20:  # 限制行数
                        break
            
            if len(result) <= 2:
                return f"无法获取 {city} 的详细天气信息，请稍后重试"
            
            return "\n".join(result[:25])
            
        except Exception as e:
            return f"获取天气失败: {str(e)}\n请检查城市名称是否正确"


# 测试
if __name__ == "__main__":
    task = WeatherTask()
    result = task.execute({"raw": "#weather 北京"})
    print(json.dumps(result, ensure_ascii=False, indent=2))
