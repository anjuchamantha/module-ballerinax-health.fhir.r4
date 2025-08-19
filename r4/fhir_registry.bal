// Copyright (c) 2023, WSO2 LLC. (http://www.wso2.com).

// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at

// http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/log;

# Hold FHIR related information in a particular deployment
public isolated class FHIRRegistry {

    private FHIRImplementationGuide[] implementationGuides = [];

    // profile map (key: profile url)
    private map<readonly & Profile> profileMap = {
        "http://hl7.org/fhir/StructureDefinition/Bundle": {
            url: "http://hl7.org/fhir/StructureDefinition/Bundle",
            resourceType: "Bundle",
            modelType: Bundle
        },
        "http://hl7.org/fhir/StructureDefinition/CodeSystem": {
            url: "http://hl7.org/fhir/StructureDefinition/CodeSystem",
            resourceType: "CodeSystem",
            modelType: CodeSystem
        },
        "http://hl7.org/fhir/StructureDefinition/OperationOutcome": {
            url: "http://hl7.org/fhir/StructureDefinition/OperationOutcome",
            resourceType: "OperationOutcome",
            modelType: OperationOutcome
        },
        "http://hl7.org/fhir/StructureDefinition/ValueSet": {
            url: "http://hl7.org/fhir/StructureDefinition/ValueSet",
            resourceType: "ValueSet",
            modelType: ValueSet
        },
        "http://hl7.org/fhir/StructureDefinition/shareablecodesystem": {
            url: "http://hl7.org/fhir/StructureDefinition/shareablecodesystem",
            resourceType: "CodeSystem",
            modelType: CodeSystem
        },
        "http://hl7.org/fhir/StructureDefinition/shareablevalueset": {
            url: "http://hl7.org/fhir/StructureDefinition/shareablevalueset",
            resourceType: "ValueSet",
            modelType: ValueSet
        }
    };

    // maintain resource type to profiles mapping
    private map<map<Profile>> resourceTypeProfiles = {};

    // resource type to profile of FHIR Base resources
    private map<readonly & Profile> fhirBaseIGProfiles = {
        "Bundle": {
            url: "http://hl7.org/fhir/StructureDefinition/Bundle",
            resourceType: "Bundle",
            modelType: Bundle
        },
        "CodeSystem": {
            url: "http://hl7.org/fhir/StructureDefinition/CodeSystem",
            resourceType: "CodeSystem",
            modelType: CodeSystem
        },
        "OperationOutcome": {
            url: "http://hl7.org/fhir/StructureDefinition/OperationOutcome",
            resourceType: "OperationOutcome",
            modelType: OperationOutcome
        },
        "ValueSet": {
            url: "http://hl7.org/fhir/StructureDefinition/ValueSet",
            resourceType: "ValueSet",
            modelType: ValueSet
        }
    };

    // search parameter map (key: resource type)
    private map<SearchParamCollection> searchParameterMap = {};

    // Operations map (key: resource type)
    private map<OperationCollection> operationsMap = {};

    // FHIR services map (key: resource type)
    private FHIRServicesCollection fhirServicesMap = {};

    public function init() {
    }

    # Add an implementation guide to the registry
    #
    # + ig - The implementation guide to be added
    # + return - An error if the implementation guide is invalid or an error occurred while adding the implementation guide
    public function addImplementationGuide(FHIRImplementationGuide ig) returns FHIRError? {
        lock {
            self.implementationGuides.push(ig);
        }

        lock {
            // add profiles to profile map
            foreach Profile profile in ig.getProfiles() {
                readonly & Profile profileClone = profile.cloneReadOnly();
                self.profileMap[profileClone.url] = profileClone;

                // Add to resource type bound profile mapping
                //ResourceDefinitionRecord resourceDefinition = check getResourceDefinition(profileClone.modelType);
                map<Profile> profiles;
                if self.resourceTypeProfiles.hasKey(profileClone.resourceType) {
                    profiles = self.resourceTypeProfiles.get(profileClone.resourceType);
                } else {
                    profiles = {};
                    self.resourceTypeProfiles[profileClone.resourceType] = profiles;
                }
                profiles[profileClone.url] = profileClone;

                // If the processed IG is FHIR base IG, we need to add it to FHIR base profile map
                if ig.getName() == FHIR_BASE_IG {
                    //ResourceDefinitionRecord resourceDef = check getResourceDefinition(profile.modelType);
                    self.fhirBaseIGProfiles[profileClone.resourceType] = profileClone;
                }
            }
        }

        lock {
            // Add search parameters
            foreach map<FHIRSearchParameterDefinition[]> paramsMap in ig.getSearchParameters() {
                foreach FHIRSearchParameterDefinition[] params in paramsMap {
                    foreach FHIRSearchParameterDefinition param in params {
                        foreach string resourceType in param.base {
                            if (self.searchParameterMap.hasKey(resourceType)) {
                                SearchParamCollection collection = self.searchParameterMap.get(resourceType);
                                if !collection.hasKey(param.name) {
                                    collection[param.name] = param;
                                }
                            } else {
                                SearchParamCollection collection = {};
                                collection[param.name] = param;
                                self.searchParameterMap[resourceType] = collection;
                            }
                        }
                    }
                }
            }
        }

        lock {
            // Add operations
            map<FHIROperationDefinition[]>? igOperationsDefinitionsMap = ig.getOperations();
            if igOperationsDefinitionsMap != () {
                foreach FHIROperationDefinition[] operationDefinitions in igOperationsDefinitionsMap {
                    foreach FHIROperationDefinition operationDefinition in operationDefinitions {
                        string[]? resources = operationDefinition.'resource;
                        if resources is string[] {
                            foreach string resourceType in resources {
                                if self.operationsMap.hasKey(resourceType) {
                                    OperationCollection collection = self.operationsMap.get(resourceType);
                                    if !collection.hasKey(operationDefinition.name) {
                                        collection[operationDefinition.name] = operationDefinition;
                                    }
                                } else {
                                    OperationCollection collection = {};
                                    collection[operationDefinition.name] = operationDefinition;
                                    self.operationsMap[resourceType] = collection;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Update terminology processor
        terminologyProcessor.addTerminology(ig.getTerminology());
    }

    # Get the resource profiles in the registry
    #
    # + resourceType - The resource type
    # + return - The profiles in the registry
    public isolated function getResourceProfiles(string resourceType) returns readonly & map<Profile & readonly> {
        lock {
            if !self.resourceTypeProfiles.hasKey(resourceType) {
                return {};
            }
            return self.resourceTypeProfiles.get(resourceType).cloneReadOnly();
        }
    }

    # Get the resource search parameters in the registry
    #
    # + resourceType - The resource type
    # + return - The search parameters in the registry
    public isolated function getResourceSearchParameters(string resourceType) returns SearchParamCollection {
        lock {
            if self.searchParameterMap.hasKey(resourceType) {
                return self.searchParameterMap.get(resourceType).cloneReadOnly();
            }
        }
        return {};
    }

    # Get the search parameters in the registry by name
    #
    # + resourceType - The resource type
    # + name - The name of the search parameter
    # + return - The search parameters in the registry
    public isolated function getResourceSearchParameterByName(string resourceType, string name) returns FHIRSearchParameterDefinition? {
        lock {
            if self.searchParameterMap.hasKey(resourceType) && self.searchParameterMap.get(resourceType).hasKey(name) {
                return self.searchParameterMap.get(resourceType).get(name).clone();
            }
        }
        return ();
    }

    # Get the resource operations in the registry.
    #
    # + resourceType - The resource type
    # + return - The operations in the registry
    public isolated function getResourceOperations(string resourceType) returns OperationCollection {
        lock {
            if self.operationsMap.hasKey(resourceType) {
                return self.operationsMap.get(resourceType).cloneReadOnly();
            }
        }
        return {};
    }

    # Register a resource operation in the registry.
    # + resourceType - The resource type
    # + opConfig - The operation configuration to be registered
    # + return - An error if the operation is invalid or an error occurred while registering the operation
    public isolated function registerResourceOperation(string resourceType, OperationConfig opConfig) returns FHIRError? {
        lock {
            OperationCollection resourceOperations = {};
            if self.operationsMap.hasKey(resourceType) {
                resourceOperations = self.operationsMap.get(resourceType);
            } else {
                self.operationsMap[resourceType] = resourceOperations;
            }
            if !resourceOperations.hasKey(opConfig.name) {
                // If the operation is not defined in resourceOperationDefinitions, it should be defined using the operationConfigMap
                if opConfig.parameters is OperationParamConfig[] {
                    log:printDebug(string `Processing operation parameters for ${opConfig.name}`);
                    FHIROperationParameterDefinition[] operationParams = [];
                    // Process operation parameters
                    // Note: This is a placeholder for any specific processing logic for operation parameters
                    foreach var item in <OperationParamConfig[]>opConfig.parameters {
                        //create FHIROperationParameterDefinition for the operation
                        FHIROperationParameterDefinition operationParam = {
                            name: item.name,
                            use: "in",
                            min: item?.min != () ? <int>item.min : 0,
                            max: item?.max != () ? <string>item.max : "*"
                        };
                        operationParams.push(operationParam);
                    }

                    FHIROperationDefinition operationDefinition = {
                        name: opConfig.name,
                        'parameter: operationParams,
                        'resource: [resourceType],
                        typeLevel: false,
                        systemLevel: false,
                        instanceLevel: false
                    };
                    json additionalProps = opConfig?.additionalProperties;
                    //access the operation level information
                    json|error metaInfo = additionalProps.meta;
                    if metaInfo is json {
                        json|error operationLevels = metaInfo.operationLevels;
                        if operationLevels is json {
                            json|error typeLevel = operationLevels.typeLevel;
                            json|error systemLevel = operationLevels.systemLevel;
                            json|error instanceLevel = operationLevels.instanceLevel;
                            // Set the operation levels
                            if typeLevel is boolean {
                                operationDefinition.typeLevel = typeLevel;
                            }
                            // Set the system and instance levels
                            if systemLevel is boolean {
                                operationDefinition.systemLevel = <boolean>systemLevel;
                            }
                            if instanceLevel is boolean {
                                operationDefinition.instanceLevel = <boolean>instanceLevel;
                            }
                        }
                    }
                    // Add the operation definition to the resourceOperations
                    resourceOperations[opConfig.name] = operationDefinition;
                }
            }
        }
    }

    # Get a resource operation in the registry by name.
    #
    # + resourceType - The resource type
    # + operation - The name of the operation
    # + return - The operation if found in the registry, otherwise ()
    public isolated function getResourceOperationByName(string resourceType,
            string operation) returns FHIROperationDefinition? {
        lock {
            if self.operationsMap.hasKey(resourceType) && self.operationsMap.get(resourceType).hasKey(operation) {
                return self.operationsMap.get(resourceType).get(operation).clone();
            }
        }
        return ();
    }

    # Get the profiles in the registry
    #
    # + url - The url of the profile
    # + return - The profiles in the registry
    public isolated function findProfile(string url) returns (readonly & Profile)? {
        lock {
            if self.profileMap.hasKey(url) {
                return self.profileMap.get(url);
            }
        }
        return ();
    }

    # Get the base profiles in the registry
    #
    # + resourceType - The resource type
    # + return - The base profile in the registry
    public isolated function findBaseProfile(string resourceType) returns (readonly & Profile)? {
        lock {
            if self.fhirBaseIGProfiles.hasKey(resourceType) {
                return self.fhirBaseIGProfiles.get(resourceType);
            }
        }
        return ();
    }

    # Check the resource type is supported by the registry
    #
    # + resourceType - The resource type
    # + return - True if the resource type is supported
    public isolated function isSupportedResource(string resourceType) returns boolean {
        lock {
            return self.resourceTypeProfiles.hasKey(resourceType);
        }
    }

    # Add a custom search parameter to the registry
    #
    # + resourceType - The resource type
    # + searchParameter - The search parameter to be added
    public isolated function addSearchParameter(string resourceType, FHIRSearchParameterDefinition searchParameter) {
        lock {
            if self.searchParameterMap.hasKey(resourceType) {
                SearchParamCollection collection = self.searchParameterMap.get(resourceType);
                if !collection.hasKey(searchParameter.name) {
                    collection[searchParameter.name] = searchParameter.clone();
                }
            }
        }
    }

    # Add a FHIR service to the registry
    #
    # + resourceType - The resource type
    # + serviceInfo - The FHIR service information
    public isolated function registerFHIRService(string resourceType, FHIRServiceInfo serviceInfo) {
        lock {
            if !self.fhirServicesMap.hasKey(resourceType) {
                self.fhirServicesMap[resourceType] = serviceInfo.clone();
            }
        }
    }

    # Get a FHIR service from the registry by resource type
    #
    # + resourceType - The resource type
    # + return - The FHIR service information if found, otherwise ()
    public isolated function getFHIRService(string resourceType) returns FHIRServiceInfo? {
        lock {
            if self.fhirServicesMap.hasKey(resourceType) {
                return self.fhirServicesMap.get(resourceType).clone();
            }
        }
        return ();
    }

    # Get all FHIR services in the registry
    # + return - A map of FHIR services where the key is the resource type
    public isolated function getAllRegisteredFHIRServices() returns FHIRServicesCollection {
        lock {
            return self.fhirServicesMap.cloneReadOnly();
        }
    }

    # Remove a FHIR service from the registry
    #
    # + resourceType - The resource type
    # + return - True if the service was removed, false if not found
    public isolated function removeFHIRService(string resourceType) returns boolean {
        lock {
            if self.fhirServicesMap.hasKey(resourceType) {
                _ = self.fhirServicesMap.remove(resourceType);
                return true;
            }
        }
        return false;
    }
}

# Search parameter map (key: parameter name)
public type SearchParamCollection map<FHIRSearchParameterDefinition>;

# Operation map (key: operation name)
public type OperationCollection map<FHIROperationDefinition>;

# FHIR services map (key: service name)
public type FHIRServicesCollection map<FHIRServiceInfo>;
