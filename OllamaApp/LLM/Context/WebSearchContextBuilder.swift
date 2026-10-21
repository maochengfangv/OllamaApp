import Foundation

struct WebSearchContextBuilder: LLMContextBuilding {
    func buildContext(for request: LLMGenerateRequest) async throws -> LLMContextEnvelope {
        guard request.webEnabled else { return .empty }

        if let weatherContext = try await fetchWeatherContext(query: request.prompt), !weatherContext.isEmpty {
            return LLMContextEnvelope(
                systemMessages: [
                    "You have access to the following real-time data. Use it to answer the user. Do not say you cannot access real-time information.\n\n\(weatherContext)"
                ],
                previewText: "【联网结果】\n" + String(weatherContext.prefix(1500))
            )
        }

        if let searchContext = try await fetchDuckDuckGoContext(query: request.prompt), !searchContext.isEmpty {
            return LLMContextEnvelope(
                systemMessages: [
                    "Web search results for: \(request.prompt)\n\(searchContext)\nUse the above information when it is relevant and cite URLs. Do not say you cannot browse."
                ],
                previewText: "【联网结果】\n" + String(searchContext.prefix(1500))
            )
        }

        return LLMContextEnvelope(
            systemMessages: [],
            previewText: "【联网结果】\n联网失败：未获取到可用结果（可能被网络限制或查询源无返回）"
        )
    }

    private struct DuckDuckGoInstantAnswer: Decodable {
        struct RelatedTopic: Decodable {
            let Text: String?
            let FirstURL: String?
            let Topics: [RelatedTopic]?
        }

        let AbstractText: String?
        let AbstractURL: String?
        let RelatedTopics: [RelatedTopic]?
    }

    private struct OpenMeteoGeocodingResponse: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }

        let results: [Result]?
    }

    private struct OpenMeteoForecastResponse: Decodable {
        struct Current: Decodable {
            let time: String
            let temperature_2m: Double?
            let apparent_temperature: Double?
            let relative_humidity_2m: Double?
            let wind_speed_10m: Double?
            let weather_code: Int?
        }

        let current: Current?
    }

    private func fetchDuckDuckGoContext(query: String) async throws -> String? {
        var components = URLComponents(string: "https://api.duckduckgo.com/")!
        components.queryItems = [
            .init(name: "q", value: query),
            .init(name: "format", value: "json"),
            .init(name: "no_html", value: "1"),
            .init(name: "skip_disambig", value: "1")
        ]

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

        let decoded = try JSONDecoder().decode(DuckDuckGoInstantAnswer.self, from: data)

        var lines: [String] = []
        if let abstract = decoded.AbstractText, !abstract.isEmpty {
            if let url = decoded.AbstractURL, !url.isEmpty {
                lines.append("Abstract: \(abstract) (\(url))")
            } else {
                lines.append("Abstract: \(abstract)")
            }
        }

        func flatten(_ items: [DuckDuckGoInstantAnswer.RelatedTopic]?) -> [DuckDuckGoInstantAnswer.RelatedTopic] {
            guard let items else { return [] }
            var out: [DuckDuckGoInstantAnswer.RelatedTopic] = []
            for item in items {
                if let topics = item.Topics, !topics.isEmpty {
                    out.append(contentsOf: flatten(topics))
                } else {
                    out.append(item)
                }
            }
            return out
        }

        let topics = flatten(decoded.RelatedTopics).compactMap { topic -> String? in
            guard let text = topic.Text, !text.isEmpty else { return nil }
            if let url = topic.FirstURL, !url.isEmpty {
                return "\(text) (\(url))"
            }
            return text
        }

        for (index, item) in topics.prefix(5).enumerated() {
            lines.append("\(index + 1). \(item)")
        }

        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(1500))
    }

    private func fetchWeatherContext(query: String) async throws -> String? {
        guard let locationName = extractLocationForWeather(query: query) else { return nil }

        var geocode = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geocode.queryItems = [
            .init(name: "name", value: locationName),
            .init(name: "count", value: "1"),
            .init(name: "language", value: "zh"),
            .init(name: "format", value: "json")
        ]

        guard let geocodeURL = geocode.url else { return nil }
        let (geocodeData, geocodeResponse) = try await URLSession.shared.data(from: geocodeURL)
        guard let geocodeHTTP = geocodeResponse as? HTTPURLResponse, geocodeHTTP.statusCode == 200 else { return nil }

        let geocodeDecoded = try JSONDecoder().decode(OpenMeteoGeocodingResponse.self, from: geocodeData)
        guard let place = geocodeDecoded.results?.first else { return nil }

        var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        forecast.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code"),
            .init(name: "timezone", value: "auto")
        ]

        guard let forecastURL = forecast.url else { return nil }
        let (forecastData, forecastResponse) = try await URLSession.shared.data(from: forecastURL)
        guard let forecastHTTP = forecastResponse as? HTTPURLResponse, forecastHTTP.statusCode == 200 else { return nil }

        let forecastDecoded = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: forecastData)
        guard let current = forecastDecoded.current else { return nil }

        let displayPlace: String = {
            var parts: [String] = [place.name]
            if let admin1 = place.admin1, !admin1.isEmpty, admin1 != place.name { parts.append(admin1) }
            if let country = place.country, !country.isEmpty { parts.append(country) }
            return parts.joined(separator: ", ")
        }()

        var lines: [String] = []
        lines.append("Realtime weather (联网模式) for: \(displayPlace)")
        lines.append("Time: \(current.time)")

        if let temperature = current.temperature_2m { lines.append("Temperature: \(String(format: "%.1f", temperature))°C") }
        if let apparentTemperature = current.apparent_temperature { lines.append("Feels like: \(String(format: "%.1f", apparentTemperature))°C") }
        if let humidity = current.relative_humidity_2m { lines.append("Humidity: \(Int(humidity))%") }
        if let wind = current.wind_speed_10m { lines.append("Wind: \(String(format: "%.1f", wind)) km/h") }
        if let code = current.weather_code { lines.append("Condition: \(openMeteoWeatherDescription(code: code)) (code \(code))") }

        lines.append("Source: https://open-meteo.com/ (geocoding-api.open-meteo.com, api.open-meteo.com)")
        return lines.joined(separator: "\n")
    }

    private func extractLocationForWeather(query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        let triggers: [String] = ["天气", "气温", "温度", "体感", "湿度", "风速", "weather", "temperature"]
        guard triggers.contains(where: { lower.contains($0.lowercased()) }) else { return nil }

        let markers: [String] = ["天气", "气温", "温度", "weather", "temperature"]
        var markerRange: Range<String.Index>?
        for marker in markers {
            if let range = trimmed.range(of: marker, options: [.backwards, .caseInsensitive]) {
                markerRange = range
                break
            }
        }

        if let markerRange {
            let before = trimmed[..<markerRange.lowerBound]
            var candidate = String(before).trimmingCharacters(in: .whitespacesAndNewlines)
            candidate = candidate.replacingOccurrences(of: "的", with: "")
            candidate = candidate.replacingOccurrences(of: "今天", with: "")
            candidate = candidate.replacingOccurrences(of: "今日", with: "")
            candidate = candidate.replacingOccurrences(of: "现在", with: "")
            candidate = candidate.replacingOccurrences(of: "实时", with: "")
            candidate = candidate.replacingOccurrences(of: "一下", with: "")
            candidate = candidate.replacingOccurrences(of: "查询", with: "")
            candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: " ，,。.!！？?、:：；;\"'“”‘’()（）[]【】"))

            if candidate.count > 8 {
                candidate = String(candidate.suffix(8))
            }

            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty { return nil }
            return candidate
        }

        return nil
    }

    private func openMeteoWeatherDescription(code: Int) -> String {
        switch code {
        case 0: return "晴朗"
        case 1, 2, 3: return "多云"
        case 45, 48: return "有雾"
        case 51, 53, 55, 56, 57: return "毛毛雨"
        case 61, 63, 65, 66, 67: return "下雨"
        case 71, 73, 75, 77: return "下雪"
        case 80, 81, 82: return "阵雨"
        case 95: return "雷暴"
        case 96, 99: return "雷暴伴冰雹"
        default: return "未知"
        }
    }
}
