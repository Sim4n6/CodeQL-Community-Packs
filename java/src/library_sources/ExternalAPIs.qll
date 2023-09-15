/**
 * Definitions for reasoning about untrusted data used in APIs defined outside the
 * database.
 */

import java
import semmle.code.java.dataflow.FlowSources
import semmle.code.java.dataflow.TaintTracking
// SECLAB: Import the CSV utils library
import semmle.code.java.dataflow.ExternalFlow as ExternalFlow

/**
 * A `Method` that is considered a "safe" external API from a security perspective.
 */
abstract class SafeExternalApiMethod extends Method { }

/** DEPRECATED: Alias for SafeExternalApiMethod */
deprecated class SafeExternalAPIMethod = SafeExternalApiMethod;

/** The default set of "safe" external APIs. */
private class DefaultSafeExternalApiMethod extends SafeExternalApiMethod {
  DefaultSafeExternalApiMethod() {
    this instanceof EqualsMethod
    or
    this.hasName(["size", "length", "compareTo", "getClass", "lastIndexOf"])
    or
    this.getDeclaringType().hasQualifiedName("org.apache.commons.lang3", "Validate")
    or
    this.hasQualifiedName("java.util", "Objects", "equals")
    or
    this.getDeclaringType() instanceof TypeString and this.getName() = "equals"
    or
    this.getDeclaringType().hasQualifiedName("com.google.common.base", "Preconditions")
    or
    this.getDeclaringType().getPackage().getName().matches("org.junit%")
    or
    this.getDeclaringType().hasQualifiedName("com.google.common.base", "Strings") and
    this.getName() = "isNullOrEmpty"
    or
    this.getDeclaringType().hasQualifiedName("org.apache.commons.lang3", "StringUtils") and
    this.getName() = "isNotEmpty"
    or
    this.getDeclaringType().hasQualifiedName("java.lang", "Character") and
    this.getName() = "isDigit"
    or
    this.getDeclaringType().hasQualifiedName("java.lang", "String") and
    this.hasName(["equalsIgnoreCase", "regionMatches"])
    or
    this.getDeclaringType().hasQualifiedName("java.lang", "Boolean") and
    this.getName() = "parseBoolean"
    or
    this.getDeclaringType().hasQualifiedName("org.apache.commons.io", "IOUtils") and
    this.getName() = "closeQuietly"
    or
    this.getDeclaringType().hasQualifiedName("org.springframework.util", "StringUtils") and
    this.hasName(["hasText", "isEmpty"])
    or
    // SECLAB: Exclude all JDK methods
    isJdkInternal(this.getCompilationUnit())
  }
}

/** A node representing data being passed to an external API. */
class ExternalApiDataNode extends DataFlow::Node {
  Call call;
  int i;

  ExternalApiDataNode() {
    (
      // Argument to call to a method
      this.asExpr() = call.getArgument(i)
      or
      // Qualifier to call to a method which returns non trivial value
      this.asExpr() = call.getQualifier() and
      i = -1 and
      not call.getCallee().getReturnType() instanceof VoidType and
      not call.getCallee().getReturnType() instanceof BooleanType
    ) and
    // Defined outside the source archive
    not call.getCallee().fromSource() and
    // Not a call to an method which is overridden in source
    not exists(Method m |
      m.getASourceOverriddenMethod() = call.getCallee().getSourceDeclaration() and
      m.fromSource()
    ) and
    // Not already modeled as a taint step (we need both of these to handle `AdditionalTaintStep` subclasses as well)
    not TaintTracking::localTaintStep(this, _) and
    not TaintTracking::defaultAdditionalTaintStep(this, _) and
    // Not a call to a known safe external API
    not call.getCallee() instanceof SafeExternalApiMethod and
    // SECLAB: Not in a test file
    not isInTestFile(call.getLocation().getFile())
  }

  /** Gets the called API `Method`. */
  Method getMethod() { result = call.getCallee() }

  /** Gets the index which is passed untrusted data (where -1 indicates the qualifier). */
  int getIndex() { result = i }

  /** Gets the description of the method being called. */
  string getMethodDescription() { result = this.getMethod().getQualifiedName() }
}

/** DEPRECATED: Alias for ExternalApiDataNode */
deprecated class ExternalAPIDataNode = ExternalApiDataNode;

/** A configuration for tracking flow from `RemoteFlowSource`s to `ExternalApiDataNode`s. */
class UntrustedDataToExternalApiConfig extends TaintTracking::Configuration {
  UntrustedDataToExternalApiConfig() { this = "UntrustedDataToExternalAPIConfig" }

  override predicate isSource(DataFlow::Node source) { source instanceof RemoteFlowSource }

  override predicate isSink(DataFlow::Node sink) { sink instanceof ExternalApiDataNode }
}

/** DEPRECATED: Alias for UntrustedDataToExternalApiConfig */
deprecated class UntrustedDataToExternalAPIConfig = UntrustedDataToExternalApiConfig;

/** A node representing untrusted data being passed to an external API. */
class UntrustedExternalApiDataNode extends ExternalApiDataNode {
  UntrustedExternalApiDataNode() { any(UntrustedDataToExternalApiConfig c).hasFlow(_, this) }

  /** Gets a source of untrusted data which is passed to this external API data node. */
  DataFlow::Node getAnUntrustedSource() {
    any(UntrustedDataToExternalApiConfig c).hasFlow(result, this)
  }
}

/** DEPRECATED: Alias for UntrustedExternalApiDataNode */
deprecated class UntrustedExternalAPIDataNode = UntrustedExternalApiDataNode;

/** An external API which is used with untrusted data. */
private newtype TExternalApi =
  /** An untrusted API method `m` where untrusted data is passed at `index`. */
  TExternalApiParameter(Method m, int index) {
    exists(UntrustedExternalApiDataNode n |
      m = n.getMethod() and
      index = n.getIndex()
    )
  }

/** An external API which is used with untrusted data. */
class ExternalApiUsedWithUntrustedData extends TExternalApi {
  /** Gets a possibly untrusted use of this external API. */
  UntrustedExternalApiDataNode getUntrustedDataNode() {
    this = TExternalApiParameter(result.getMethod(), result.getIndex())
  }

  /** Gets the number of untrusted sources used with this external API. */
  int getNumberOfUntrustedSources() {
    result = count(this.getUntrustedDataNode().getAnUntrustedSource())
  }

  /** Gets a textual representation of this element. */
  string toString() {
    exists(Method m, int index |
      this = TExternalApiParameter(m, index) and
      // SECLAB: use the CSV library to get the 6 first columns
      result = asPartialModel(m) + index.toString()
    )
  }
}

/** DEPRECATED: Alias for ExternalApiUsedWithUntrustedData */
deprecated class ExternalAPIUsedWithUntrustedData = ExternalApiUsedWithUntrustedData;

// SECLAB: predicates from https://github.com/github/codeql/blob/main/java/ql/src/utils/modelgenerator/internal/CaptureModelsSpecific.qll
// We cannot import them directly as they are based on TargetApiSpecific which checks for `fromSource()`
private Method superImpl(Method m) {
  result = m.getAnOverride() and
  not exists(result.getAnOverride()) and
  not m instanceof ToStringMethod
}

private string isExtensible(RefType ref) {
  if ref.isFinal() then result = "false" else result = "true"
}

private string typeAsModel(RefType type) {
  result = type.getCompilationUnit().getPackage().getName() + ";" + type.nestedName()
}

private RefType bestTypeForModel(Method api) {
  if exists(superImpl(api))
  then superImpl(api).fromSource() and result = superImpl(api).getDeclaringType()
  else result = api.getDeclaringType()
}

private string typeAsSummaryModel(Method api) { result = typeAsModel(bestTypeForModel(api)) }

private predicate partialModel(Method api, string type, string name, string parameters) {
  type = typeAsSummaryModel(api) and
  name = api.getName() and
  parameters = ExternalFlow::paramsString(api)
}

string asPartialModel(Method api) {
  exists(string type, string name, string parameters |
    partialModel(api, type, name, parameters) and
    result =
      type + ";" //
        + isExtensible(bestTypeForModel(api)) + ";" //
        + name + ";" //
        + parameters + ";" //
        + /* ext + */ ";" //
  )
}

private predicate isInTestFile(File file) {
  file.getAbsolutePath().matches("%src/test/%") or
  file.getAbsolutePath().matches("%/guava-tests/%") or
  file.getAbsolutePath().matches("%/guava-testlib/%")
}

private predicate isJdkInternal(CompilationUnit cu) {
  cu.getPackage().getName().matches("org.graalvm%") or
  cu.getPackage().getName().matches("com.sun%") or
  cu.getPackage().getName().matches("sun%") or
  cu.getPackage().getName().matches("jdk%") or
  cu.getPackage().getName().matches("java2d%") or
  cu.getPackage().getName().matches("build.tools%") or
  cu.getPackage().getName().matches("propertiesparser%") or
  cu.getPackage().getName().matches("org.jcp%") or
  cu.getPackage().getName().matches("org.w3c%") or
  cu.getPackage().getName().matches("org.ietf.jgss%") or
  cu.getPackage().getName().matches("org.xml.sax%") or
  cu.getPackage().getName().matches("com.oracle%") or
  cu.getPackage().getName().matches("org.omg%") or
  cu.getPackage().getName().matches("org.relaxng%") or
  cu.getPackage().getName() = "compileproperties" or
  cu.getPackage().getName() = "transparentruler" or
  cu.getPackage().getName() = "genstubs" or
  cu.getPackage().getName() = "netscape.javascript" or
  cu.getPackage().getName() = "" or
  // SECLAB add java package
  cu.getPackage().getName().matches("java.%") or
  cu.getPackage().getName().matches("javax.%")
}