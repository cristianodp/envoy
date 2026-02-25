#include "source/common/common/base_logger.h"
#include <cstdlib>

namespace Envoy {
namespace Logger {

// Original Envoy text format (default when ENVOY_LOG_FORMAT is not set).
const char* Logger::DEFAULT_LOG_FORMAT = "[%Y-%m-%d %T.%e][%t][%l][%n] [%g:%#] %v";
// JSON format activated by setting ENVOY_LOG_FORMAT=json.
const char* Logger::JSON_LOG_FORMAT =
  "{\"ts\":\"%Y-%m-%dT%T.%eZ\",\"thread\":\"%t\",\"level\":\"%l\",\"logger\":\"%n\",\"source\":\"%g:%#\",\"msg\":%Q}";

Logger::Logger(std::shared_ptr<spdlog::logger> logger) : logger_(logger) {
  // Choose format: ENVOY_LOG_FORMAT=json activates structured JSON output;
  // any other value (or unset) keeps the default Envoy text format.
  const char* env = std::getenv("ENVOY_LOG_FORMAT");
  const char* format = (env != nullptr && std::string_view(env) == "json")
                           ? JSON_LOG_FORMAT
                           : DEFAULT_LOG_FORMAT;
  auto formatter = std::make_unique<spdlog::pattern_formatter>();
  formatter->add_flag<JsonMsgFormatter>('Q').set_pattern(format);
  logger_->set_formatter(std::move(formatter));
  logger_->set_level(spdlog::level::trace);
  logger_->flush_on(spdlog::level::critical);
}

} // namespace Logger
} // namespace Envoy
