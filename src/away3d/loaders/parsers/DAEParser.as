package away3d.loaders.parsers
{
	import away3d.arcane;
	import away3d.containers.ObjectContainer3D;
	import away3d.core.base.Geometry;
	import away3d.entities.Mesh;
	import away3d.library.assets.BitmapDataAsset;
	import away3d.loaders.misc.ResourceDependency;
	import away3d.materials.BitmapMaterial;
	import away3d.materials.ColorMaterial;
	
	import flash.geom.Matrix3D;
	import flash.net.URLRequest;
	
	use namespace arcane;
	
	/**
	 * Provides a parser for the Collada (DAE) data type.
	 */
	public class DAEParser extends ParserBase
	{	
		private var _doc : XML;
		private var _ns : Namespace;
		private var _parseState : uint = 0;
		private var _imageList : XMLList;
		private var _imageCount : uint;
		private var _currentImage : uint;
		private var _dependencyCount : uint = 0;
		
		private var _libImages : Object;
		private var _libMaterials : Object;
		private var _libEffects : Object;
		private var _libGeometries : Object;
		
		private var _scene : DAEScene;
		private var _root : DAEVisualScene;
		
		private var _defaultBitmapMatrial:BitmapMaterial = new BitmapMaterial(defaultBitmapData, true, true);
		private var _defaultColorMaterial:ColorMaterial = new ColorMaterial(0xff0000);
		
		private static var _numInstances:uint = 0;
		
		public function DAEParser()
		{
			super(ParserDataFormat.PLAIN_TEXT);
		}
		
		/**
		 * Indicates whether or not a given file extension is supported by the parser.
		 * @param extension The file extension of a potential file to be parsed.
		 * @return Whether or not the given file type is supported.
		 */
		public static function supportsType(extension : String) : Boolean 
		{
			extension = extension.toLowerCase();
			return extension == "dae";
		}
		
		/**
		 * Tests whether a data block can be parsed by the parser.
		 * @param data The data block to potentially be parsed.
		 * @return Whether or not the given data is supported.
		 */
		public static function supportsData(data : *) : Boolean 
		{
			// TODO
			return true;
		}
		
		/**
		 * @inheritDoc
		 */
		override arcane function resolveDependency(resourceDependency:ResourceDependency):void 
		{
			if (resourceDependency.assets.length != 1)
				return;
			
			var resource:BitmapDataAsset = resourceDependency.assets[0] as BitmapDataAsset;
			
			_dependencyCount--;
			
			if (resource && resource.bitmapData)
			{
				var image:DAEImage = _libImages[ resourceDependency.id ] as DAEImage;
				
				if (image)
				{
					image.resource = resource;
					if (!isBitmapDataValid(resource.bitmapData))
					{
						// TODO: handle odd-sized bitmaps
					}
				}
			}
			
			if (_dependencyCount == 0)
				_parseState = DAEParserState.PARSE_MATERIALS;
		}
		
		/**
		 * @inheritDoc
		 */
		override arcane function resolveDependencyFailure(resourceDependency:ResourceDependency):void
		{			
			if (resourceDependency.assets.length != 1)
				return;
			
			var resource:BitmapDataAsset = resourceDependency.assets[0] as BitmapDataAsset;
			
			_dependencyCount--;
			
			if (_dependencyCount == 0)
				_parseState = DAEParserState.PARSE_MATERIALS;
		}
		
		/**
		 * @inheritDoc
		 */
		protected override function proceedParsing() : Boolean
		{
			switch (_parseState)
			{
				case DAEParserState.LOAD_XML:
					_doc = new XML(getTextData());
					_ns = _doc.namespace();
					
					_libImages = new Object();
					_imageList = _doc._ns::library_images._ns::image;
					_imageCount = _dependencyCount = _imageList.length();
					_currentImage = 0;
					
					_parseState = _imageCount > 0 ? DAEParserState.PARSE_IMAGES : DAEParserState.PARSE_MATERIALS;
					break;
				
				case DAEParserState.PARSE_IMAGES:
					parseLibImages();
					break;
				
				case DAEParserState.PARSE_MATERIALS:
					parseLibMaterials();
					parseLibEffects();
					_parseState = DAEParserState.PARSE_GEOMETRIES;
					break;
				
				case DAEParserState.PARSE_GEOMETRIES:
					parseLibGeometries();
					_parseState = DAEParserState.PARSE_VISUAL_SCENE;
					break;
				
				case DAEParserState.PARSE_VISUAL_SCENE:
					_scene = null;
					_root = null;
					
					if (_doc.._ns::scene && _doc.._ns::scene.length())
					{
						_scene = new DAEScene(_doc.._ns::scene[0]);
						
						var list : XMLList = _doc.._ns::visual_scene.(@id == _scene.instance_visual_scene.url);
						
						if (list.length())
						{
							var o : ObjectContainer3D = new ObjectContainer3D();
							
							_root = new DAEVisualScene(this, list[0]);
							
							finalize(_root, o);
							
							finalizeAsset(o, "COLLADA_" + (_numInstances++));
							
							o.scaleX = -o.scaleX;
						}
					}
					_parseState = DAEParserState.PARSE_COMPLETE;
					break;
				
				case DAEParserState.PARSE_COMPLETE:
					return PARSING_DONE;
					break;
				
				default:
					break;
			}
			return MORE_TO_PARSE;
		}
		
		private function finalize(node : DAENode, parent : ObjectContainer3D = null):void
		{
			var o : ObjectContainer3D = node.instance_geometries.length ? new Mesh(new BitmapMaterial(defaultBitmapData)) : new ObjectContainer3D();
			var mesh:Mesh = o as Mesh;
			var i:int, j:int;
			
			if (parent)
				parent.addChild(o);
			
			for (i = 0; i < node.instance_geometries.length; i++)
			{
				var instance:DAEInstanceGeometry = node.instance_geometries[i];
				var geom:DAEGeometry = _libGeometries[instance.url];
				var geometry:Geometry = null;
				
				if (geom.mesh) 
				{
					geom.mesh.createGeometry(mesh.geometry);
				}
			}
			
			if (mesh)
			{
				for(j = 0; j < mesh.subMeshes.length; j++)
				{
					if(mesh.subMeshes[j].subGeometry.UVData.length)
					{
						mesh.subMeshes[j].material = _defaultBitmapMatrial; //new BitmapMaterial(defaultBitmapData);
					}
					else
					{
						mesh.subMeshes[j].material = _defaultColorMaterial;
					}
				}
			}
		
			o.transform = node.matrix;
			
			for (i = 0; i < node.nodes.length; i++)
			{
				finalize(node.nodes[i], o);
			}
			
			finalizeAsset(o, node.id);
		}
		
		private function parseLibEffects() : void
		{
			var list:XMLList = _doc._ns::library_effects._ns::effect;
			var count:uint = list.length();
			
			_libEffects = new Object();
			
			for (var i:int = 0; i < count; i++)
			{
				var effect:DAEEffect = new DAEEffect(list[i]);
				
				_libEffects[effect.id] = effect;
			}
		}
		
		private function parseLibGeometries() : void
		{
			var list:XMLList = _doc._ns::library_geometries._ns::geometry;
			var count:uint = list.length();
			
			_libGeometries = new Object();
			
			for (var i:int = 0; i < count; i++)
			{
				var geometry:DAEGeometry = new DAEGeometry(list[i]);
				
				_libGeometries[geometry.id] = geometry;
			}
		}
		
		private function parseLibImages() : void
		{
			for (var i:int = 0; i < _dependencyCount; i++)
			{
				var image : DAEImage = new DAEImage(_imageList[i]);	
				
				_libImages[image.id] = image;
				
				addDependency(image.id, new URLRequest(image.init_from));
			}
			pauseAndRetrieveDependencies();
		}
		
		private function parseLibMaterials() : void
		{
			var list:XMLList = _doc._ns::library_materials._ns::material;
			var count:uint = list.length();
			
			_libMaterials = new Object();
			
			for (var i:int = 0; i < count; i++)
			{
				var material:DAEMaterial = new DAEMaterial(list[i]);
				
				_libMaterials[material.id] = material;
			}
		}
		
		public function get geometries() : Object
		{
			return _libGeometries;
		}
		
		public function get effects() : Object
		{
			return _libEffects;
		}
		
		public function get images() : Object
		{
			return _libImages;
		}
		
		public function get materials() : Object
		{
			return _libMaterials;
		}
	}
}
import away3d.core.base.Geometry;
import away3d.core.base.SubGeometry;
import away3d.core.base.data.Vertex;
import away3d.library.assets.BitmapDataAsset;
import away3d.loaders.parsers.DAEParser;

import flash.geom.Matrix3D;
import flash.geom.Vector3D;

class DAEElement
{
	public var id : String;
	public var name : String;
	public var sid : String;
	
	protected var ns : Namespace;
	
	public function DAEElement(element : XML = null)
	{
		if (element)
			deserialize(element);
	}
	
	public function deserialize(element : XML) : void
	{
		ns = element.namespace();
		id = element.@id.toString();
		name = element.@name.toString();
		sid = element.@sid.toString();
	}
	
	protected function getRootElement(element : XML) : XML
	{
		var tmp : XML = element;
		
		while (tmp.name().localName != "COLLADA")
		{
			tmp = tmp.parent();		
		}
		
		return (tmp.name().localName == "COLLADA" ? tmp : null);
	}
	
	protected function readFloatArray(element : XML) : Vector.<Number>
	{
		var raw : String = readText(element);
		var parts : Array = raw.split(/\s+/);
		var floats : Vector.<Number> = new Vector.<Number>();
		var i : int;
		
		for (i = 0; i < parts.length; i++)
		{
			floats.push(parseFloat(parts[i]));
		}
		
		return floats;
	}
	
	protected function readIntArray(element : XML) : Vector.<int>
	{
		var raw : String = readText(element);
		var parts : Array = raw.split(/\s+/);
		var ints : Vector.<int> = new Vector.<int>();
		var i : int;
		
		for (i = 0; i < parts.length; i++)
		{
			ints.push(parseInt(parts[i], 10));
		}
		
		return ints;
	}
	
	protected function readStringArray(element : XML) : Vector.<String>
	{
		var raw : String = readText(element);
		var parts : Array = raw.split(/\s+/);
		var strings : Vector.<String> = new Vector.<String>();
		var i : int;
		
		for (i = 0; i < parts.length; i++)
		{
			strings.push(parts[i]);
		}
		
		return strings;
	}
	
	protected function readIntAttr(element : XML, name : String, defaultValue : int = 0) : int
	{
		var v : int = parseInt(element.@[name], 10);
		v = v == 0 ? defaultValue : v;
		return v;
	}
	
	protected function readText(element : XML) : String
	{
		return trimString(element.text().toString());	
	}
	
	protected function trimString(s : String) : String
	{
		return s.replace(/^\s+/, "").replace(/\s+$/, "");
	}
}

class DAEImage extends DAEElement
{
	public var init_from : String;
	public var resource : BitmapDataAsset;
	
	public function DAEImage(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		init_from = readText(element.ns::init_from[0]);
		resource = null;
	}
}

class DAEParam extends DAEElement
{
	public var type : String;
	
	public function DAEParam(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		this.type = element.@type.toString();
	}
}

class DAEAccessor extends DAEElement
{
	public var params : Vector.<DAEParam>;
	public var source : String;
	public var stride : int;
	
	public function DAEAccessor(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		this.params = new Vector.<DAEParam>();
		this.source = element.@source.toString().replace(/^#/, "");
		this.stride = readIntAttr(element, "stride", 1);

		var list:XMLList = element.ns::param;
		
		for (var i:int = 0; i < list.length(); i++)
		{
			this.params.push(new DAEParam(list[i]));			
		}
	}
}

class DAESource extends DAEElement
{
	public var accessor : DAEAccessor;
	public var type : String;
	public var floats : Vector.<Number>;
	public var ints : Vector.<int>;
	public var bools : Vector.<Boolean>;
	public var strings : Vector.<String>;
	
	public function DAESource(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		var list:XMLList = element.children();
		
		for (var i:int = 0; i < list.length(); i++)
		{
			var child:XML = list[i];
			var name:String = child.name().localName;
			
			switch (name)
			{
				case "float_array":
					this.type = name;
					this.floats = readFloatArray(child);
					break;
				case "int_array":
					this.type = name;
					this.ints = readIntArray(child);
					break;
				case "bool_array":
					throw new Error("Cannot handle bool_array");
					break;
				case "Name_array":
				case "IDREF_array":
					this.type = name;
					this.strings = readStringArray(child);
					break;
				case "technique_common":
					this.accessor = new DAEAccessor(child.ns::accessor[0]);
					break;
				default:
					break;
			}
		}
	}
}

class DAEInput extends DAEElement
{
	public var semantic : String;
	public var source : String;
	public var offset : int;
	public var set : int;
	
	public function DAEInput(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		this.semantic = element.@semantic.toString();
		this.source = element.@source.toString().replace(/^#/, "");
		this.offset = readIntAttr(element, "offset");
		this.set = readIntAttr(element, "set");
	}
}

class DAEVertex
{
	public var x:Number;
	public var y:Number;
	public var z:Number;
	public var nx:Number;
	public var ny:Number;
	public var nz:Number;
	public var uvx:Number;
	public var uvy:Number;
	public var uvx2:Number;
	public var uvy2:Number;
	public var numTexcoordSets:uint = 0;
	public var index:uint = NaN;
	
	public function DAEVertex(numTexcoordSets:uint)
	{
		this.numTexcoordSets = numTexcoordSets;
		x = y = z = nx = ny = nz = uvx = uvy = uvx2 = uvy2 = 0;	
	}
	
	public function get hash() : String
	{
		var s : String = format(x);
		s += "_" + format(y);
		s += "_" + format(z);
		s += "_" + format(nx);
		s += "_" + format(ny);
		s += "_" + format(nz);
		s += "_" + format(uvx);
		s += "_" + format(uvy);
		s += "_" + format(uvx2);
		s += "_" + format(uvy2);
		return s;
	}
	
	public function createVertex():Vertex
	{
		return new Vertex(x, y, z, index);
	}
	
	private function format(v : Number, numDecimals : int = 2) : String
	{
		return v.toFixed(numDecimals);
	}
}

class DAEFace
{
	public var vertices:Vector.<DAEVertex>;
	
	public function DAEFace()
	{
		this.vertices = new Vector.<DAEVertex>();	
	}
}

class DAEPrimitive extends DAEElement
{
	public var type : String;
	public var material : String;
	public var count : int;
	
	private var _inputs : Vector.<DAEInput>;
	private var _p : Vector.<int>;
	private var _vcount : Vector.<int>;
	private var _texcoordSets : Vector.<int>;
	
	public function DAEPrimitive(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		this.type = element.name().localName;
		this.material = element.@material.toString();
		this.count = readIntAttr(element, "count", 0);
		
		_inputs = new Vector.<DAEInput>();
		_p = null;
		_vcount = null;
		
		var list:XMLList = element.ns::input;
		var i:int;
		
		for (i = 0; i < list.length(); i++)
		{
			_inputs.push(new DAEInput(list[i]));
		}
		
		if (element.ns::p && element.ns::p.length())
			_p = readIntArray(element.ns::p[0]);
		
		if (element.ns::vcount && element.ns::vcount.length())
			_vcount = readIntArray(element.ns::vcount[0]);
	}
	
	/**
	 * Creates the primitive. Typically called after deserialization.
	 * 
	 * @param	mesh
	 * 
	 * @return Array of DAEFace or null on failure.
	 */ 
	public function create(mesh : DAEMesh) : Vector.<DAEFace>
	{
		if (!prepareInputs(mesh))
			return null;
		
		var faces:Vector.<DAEFace> = new Vector.<DAEFace>();
		var input:DAEInput;
		var source:DAESource;
		var numInputs:uint = _inputs.length;
		var idx:int = 0, index:int;
		var i:int, j:int;
		var x:Number, y:Number, z:Number;
		var vertexIndex:uint = 0;
		var vertexDict:Object = new Object();
		
		while (idx < _p.length)
		{
			var vcount:int = _vcount != null ? _vcount.shift() : 3;
			var face:DAEFace = new DAEFace();
			
			for (i = 0; i < vcount; i++)
			{
				var t:int = i * numInputs;
				var vertex:DAEVertex = new DAEVertex(_texcoordSets.length);
				
				for (j = 0; j < _inputs.length; j++)
				{
					input = _inputs[j];
					index = _p[idx + t + input.offset];
					source = mesh.sources[input.source] as DAESource;
					
					switch (input.semantic)
					{
						case "VERTEX":
							vertex.x = source.floats[(index*3)+0];
							vertex.y = source.floats[(index*3)+1];
							vertex.z = source.floats[(index*3)+2];
							vertex.index = vertexIndex++;
							break;
						case "NORMAL":
							vertex.nx = source.floats[(index*3)+0];
							vertex.ny = source.floats[(index*3)+1];
							vertex.nz = source.floats[(index*3)+2];
							break;
						case "TEXCOORD":
							if (source.accessor.params.length == 2)
							{
								if (input.set == _texcoordSets[0])
								{
									vertex.uvx = source.floats[(index*2)+0];
									vertex.uvy = source.floats[(index*2)+1];
								}
								else
								{
									vertex.uvx2 = source.floats[(index*2)+0];
									vertex.uvy2 = source.floats[(index*2)+1];
								}
							}
							else
							{
								if (input.set == _texcoordSets[0])
								{
									vertex.uvx = source.floats[(index*3)+0];
									vertex.uvy = source.floats[(index*3)+1];
								}
								else
								{
									vertex.uvx2 = source.floats[(index*3)+0];
									vertex.uvy2 = source.floats[(index*3)+1];
								}
							}
							break;
						default:
							break;
					}
				}
				var hash:String = vertex.hash;
				if (vertexDict[hash])
				{
					face.vertices.push(vertexDict[hash]);
				}
				else
				{
					vertexDict[hash] = vertex;
					face.vertices.push(vertex);
				}
			}
			if (face.vertices.length > 3)
			{
				// triangulate
				var v0:DAEVertex = face.vertices.shift();
				var f:DAEFace = new DAEFace();
				
				f.vertices.push(v0);
				
				for (var k:int = 0; k < face.vertices.length; k++)
				{
					f.vertices.push(face.vertices[k]);
					if (f.vertices.length == 3)
					{
						faces.push(f);
						f = new DAEFace();
						f.vertices.push(v0);
						f.vertices.push(face.vertices[k]);
					}
				}
			}
			else
			{
				faces.push(face);
			}
			idx += (vcount * numInputs);
		}
		return faces;
	}
	
	private function prepareInputs(mesh : DAEMesh) : Boolean
	{
		var input:DAEInput;
		var i:int, j:int;
		var result : Boolean = true;
		
		_texcoordSets = new Vector.<int>();
		
		for (i = 0; i < _inputs.length; i++)
		{
			input = _inputs[i];
			
			if (input.semantic == "TEXCOORD")
			{
				_texcoordSets.push(input.set);
			}
			
			if (!mesh.sources[input.source])
			{
				result = false;
				if (input.source == mesh.vertices.id)
				{
					for (j = 0; j < mesh.vertices.inputs.length; j++)
					{
						if (mesh.vertices.inputs[j].semantic == "POSITION")
						{
							input.source = mesh.vertices.inputs[j].source;
							result = true;
							break;
						}
					}
				}
			}
		}
		
		return result;
	}
}

class DAEVertices extends DAEElement
{
	public var mesh : DAEMesh;
	public var inputs : Vector.<DAEInput>;
	
	public function DAEVertices(mesh : DAEMesh, element : XML = null)
	{
		this.mesh = mesh;
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		var list:XMLList = element.ns::input;
		var i:int;
		
		this.inputs = new Vector.<DAEInput>();
		
		for (i = 0; i < list.length(); i++)
		{
			this.inputs.push(new DAEInput(list[i]));
		}
	}
}

class DAEGeometry extends DAEElement
{	
	public var mesh : DAEMesh;
	
	public function DAEGeometry(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		this.mesh = null;
		
		if (element.ns::mesh && element.ns::mesh.length())
		{
			this.mesh = new DAEMesh(this, element.ns::mesh[0]);
		}
	}
}

class DAEMesh extends DAEElement
{	
	public var geometry : DAEGeometry;
	public var sources : Object;
	public var vertices : DAEVertices;
	public var primitives : Vector.<DAEPrimitive>;
	
	public function DAEMesh(geometry : DAEGeometry, element : XML = null)
	{
		this.geometry = geometry;
		
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		this.sources = new Object();
		this.vertices = null;
		this.primitives = new Vector.<DAEPrimitive>();
		
		var list:XMLList = element.children();
		var i:int;
		
		for (i = 0; i < list.length(); i++)
		{
			var child:XML = list[i];
			var name:String = child.name().localName;
			
			switch (name)
			{
				case "source":
					var source:DAESource = new DAESource(child);
					this.sources[source.id] = source;
					break;
				case "vertices":
					this.vertices = new DAEVertices(this, child);
					break;
				case "triangles":
				case "polylist":
				case "polygon":
					this.primitives.push(new DAEPrimitive(child));
					break;
				default:
					break;
			}
		}
	}
	
	public function createGeometry(geometry : Geometry) : void
	{
		for (var i:int = 0; i < this.primitives.length; i++)
		{
			var faces:Vector.<DAEFace> = this.primitives[i].create(this);
			
			if (faces)
			{
				var sub:SubGeometry = new SubGeometry();
				var indexData:Vector.<uint> = new Vector.<uint>();
				var vertexData:Vector.<Number> = new Vector.<Number>();
				var uvData:Vector.<Number> = new Vector.<Number>();
				var uvData2:Vector.<Number> = new Vector.<Number>();
				
				for (var j:int = 0; j < faces.length; j++)
				{
					var face:DAEFace = faces[j];					

					for (var k:int = 0; k < face.vertices.length; k++)
					{
						var v:DAEVertex = face.vertices[k];
						
						indexData.push(v.index);
						vertexData.push(v.x, v.y, v.z);
						
						if (v.numTexcoordSets > 0)
						{
							uvData.push(v.uvx, v.uvy);
							if (v.numTexcoordSets > 1)
								uvData2.push(v.uvx2, v.uvy2);
						}
					}
				}
				
				sub.autoDeriveVertexNormals = true;
				sub.autoDeriveVertexTangents = true;
				sub.updateVertexData(vertexData);
				if (vertexData.length == uvData.length*(3/2))
				{
					sub.updateUVData(uvData);
					if (uvData.length == uvData2.length)
						sub.updateSecondaryUVData(uvData2);
					
					indexData.reverse();
					sub.updateIndexData(indexData);
					
					geometry.addSubGeometry(sub);
				}
				
			}
		}
	}
}

class DAEBindMaterial extends DAEElement
{	
	public var instance_material : Vector.<DAEInstanceMaterial>;
	
	public function DAEBindMaterial(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		this.instance_material = new Vector.<DAEInstanceMaterial>();
		
		var children:XMLList = element.children();
		var i:int, j:int;
		
		for (i = 0; i < children.length(); i++)
		{
			var child:XML = children[i];
			var name:String = child.name().localName;
			
			switch (name)
			{
				case "technique_common":
					for (j = 0; j < child.children().length(); j++)
					{
						this.instance_material.push(new DAEInstanceMaterial(child.children()[j]));
					}
					break;
				default:
					break;
			}
		}
	}
}

class DAEInstance extends DAEElement
{	
	public var url : String;
	
	public function DAEInstance(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		this.url = element.@url.toString().replace(/^#/, "");
	}
}

class DAEInstanceCamera extends DAEInstance
{	
	public function DAEInstanceCamera(element : XML = null)
	{
		super(element);
	}
}

class DAEInstanceEffect extends DAEInstance
{	
	public function DAEInstanceEffect(element : XML = null)
	{
		super(element);
	}
}

class DAEInstanceGeometry extends DAEInstance
{	
	public var bind_material : DAEBindMaterial;
	
	public function DAEInstanceGeometry(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		this.bind_material = null;
		
		var children:XMLList = element.children();
		var i:int;
		
		for (i = 0; i < children.length(); i++)
		{
			var child:XML = children[i];
			var name:String = child.name().localName;
			
			switch (name)
			{
				case "bind_material":
					this.bind_material = new DAEBindMaterial(child);
					break;
				default:
					break;
			}
		}
	}
}

class DAEInstanceMaterial extends DAEInstance
{	
	public var target : String;
	public var symbol : String;
	
	public function DAEInstanceMaterial(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		this.target = element.@target.toString().replace(/^#/, "");
		this.symbol = element.@symbol.toString();
	}
}

class DAEInstanceNode extends DAEInstance
{	
	public function DAEInstanceNode(element : XML = null)
	{
		super(element);
	}
}

class DAEInstancePhysicsScene extends DAEInstance
{	
	public function DAEInstancePhysicsScene(element : XML = null)
	{
		super(element);
	}
}

class DAEInstanceVisualScene extends DAEInstance
{	
	public function DAEInstanceVisualScene(element : XML = null)
	{
		super(element);
	}
}

class DAEColor
{
	public var r : Number;
	public var g : Number;
	public var b : Number;
	public var a : Number;
}

class DAETexture
{
	public var texture : String;
	public var texcoord : String;
}

class DAEColorOrTexture extends DAEElement
{	
	public var color : DAEColor;
	public var texture : DAETexture;
	
	public function DAEColorOrTexture(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		var children:XMLList = element.children();
		var i:int;
		
		this.color = null;
		this.texture = null;
		
		for (i = 0; i < children.length(); i++)
		{
			var child:XML = children[i];
			var name:String = child.name().localName;
			
			switch (name)
			{
				case "color":
					var values:Vector.<Number> = readFloatArray(child);
					this.color = new DAEColor();
					this.color.r = values[0];
					this.color.g = values[1];
					this.color.b = values[2];
					this.color.a = values.length > 3 ? values[3] : 1.0;
					break;
				case "texture":
					this.texture = new DAETexture();
					this.texture.texcoord = child.@texcoord.toString();
					this.texture.texture = child.@texture.toString();
					break;
				default:
					break;
			}
		}
	}
}

class DAESurface extends DAEElement
{	
	public var type : String;
	public var init_from : String;
	
	public function DAESurface(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		this.type = element.@type.toString();
		this.init_from = readText(element.ns::init_from[0]);
	}
}

class DAESampler2D extends DAEElement
{	
	public var source : String;

	public function DAESampler2D(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		this.source = readText(element.ns::source[0]);
	}
}

class DAEShader extends DAEElement
{	
	public var type : String;
	public var props : Object;
	
	public function DAEShader(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		this.type = element.name().localName;
		this.props = new Object();
		
		var children:XMLList = element.children();
		var i:int;
		
		for (i = 0; i < children.length(); i++)
		{
			var child:XML = children[i];
			var name:String = child.name().localName;
			
			switch (name)
			{
				case "ambient":
				case "diffuse":
				case "specular":
				case "emission":
				case "transparent":
					this.props[name] = new DAEColorOrTexture(child);
					break;
				case "shininess":
				case "reflectivity":
				case "transparency":
					this.props[name] = parseFloat(readText(child.ns::float[0]));
					break;
				default:
					trace("[WARNING] unhandled DAEShader property: " + name);
					break;
			}
		}
	}
}

class DAEEffect extends DAEElement
{	
	public var shader : DAEShader;
	public var surface : DAESurface;
	public var sampler : DAESampler2D;
	
	public function DAEEffect(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		var children:XMLList = element.children();
		var i:int;
		
		this.shader = null;
		this.surface = null;
		this.sampler = null;
		
		for (i = 0; i < children.length(); i++)
		{
			var child:XML = children[i];
			var name:String = child.name().localName;
			
			switch (name)
			{
				case "profile_COMMON":
					deserializeProfile(child);
					break;
				case "extra":
					break;
				default:
					break;
			}
		}
	}
	
	private function deserializeProfile(element : XML) : void
	{
		var children:XMLList = element.children();
		var i:int;
		
		for (i = 0; i < children.length(); i++)
		{
			var child:XML = children[i];
			var name:String = child.name().localName;
			
			switch (name)
			{
				case "technique":
					deserializeShader(child);
					break;
				case "newparam":
					deserializeNewParam(child);
					break;
				case "extra":
					break;
				default:
					break;
			}
		}
	}
	
	private function deserializeNewParam(element : XML) : void
	{
		var children:XMLList = element.children();
		var i:int;
		
		for (i = 0; i < children.length(); i++)
		{
			var child:XML = children[i];
			var name:String = child.name().localName;
			
			switch (name)
			{
				case "surface":
					this.surface = new DAESurface(child);
					break;
				case "sampler2D":
					this.sampler = new DAESampler2D(child);
					break;
				default:
					trace("[WARNING] unhandled newparam: " + name);
					break;
			}
		}
	}
	
	private function deserializeShader(technique : XML) : void
	{
		var children:XMLList = technique.children();
		var i:int;
		
		this.shader = null;
		
		for (i = 0; i < children.length(); i++)
		{
			var child:XML = children[i];
			var name:String = child.name().localName;
			
			switch (name)
			{
				case "constant":
				case "lambert":
				case "blinn":
				case "phong":
					this.shader = new DAEShader(child);
					break;
				default:
					break;
			}
		}
	}
}

class DAEMaterial extends DAEElement
{	
	public var instance_effect : DAEInstanceEffect;
	
	public function DAEMaterial(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		var children:XMLList = element.children();
		var i:int;
		
		this.instance_effect = null;
		
		for (i = 0; i < children.length(); i++)
		{
			var child:XML = children[i];
			var name:String = child.name().localName;
			
			switch (name)
			{
				case "instance_effect":
					this.instance_effect = new DAEInstanceEffect(child);
					break;
				default:
					break;
			}
		}
	}
}

class DAETransform extends DAEElement
{
	public var type : String;
	public var data : Vector.<Number>;
	
	public function DAETransform(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		this.type = element.name().localName;
		this.data = readFloatArray(element);
	}
	
	public function get matrix() : Matrix3D
	{
		var matrix : Matrix3D = new Matrix3D();
		
		switch (this.type)
		{
			case "matrix":
				matrix = new Matrix3D(this.data);
				matrix.transpose();
				break;
			case "scale":
				matrix.appendScale(this.data[0], this.data[1], this.data[2]);
				break;
			case "translate":
				matrix.appendTranslation(this.data[0], this.data[1], this.data[2]);
				break;
			case "rotate":
				var axis:Vector3D = new Vector3D(this.data[0], this.data[1], this.data[2]);
				matrix.appendRotation(this.data[3], axis);
				break;
			default:
				break;
		}
		
		return matrix;
	}
}

class DAENode extends DAEElement
{
	public var parser : DAEParser;
	public var nodes : Vector.<DAENode>;
	public var transforms : Vector.<DAETransform>;
	public var instance_cameras : Vector.<DAEInstanceCamera>;
	public var instance_geometries : Vector.<DAEInstanceGeometry>;
	
	public function DAENode(parser : DAEParser, element : XML = null)
	{
		this.parser = parser;
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		var root : XML = getRootElement(element);
		var instances : XMLList;
		var instance : DAEInstance;
		var children:XMLList = element.children();
		var i:int;
		
		this.nodes = new Vector.<DAENode>();
		this.transforms = new Vector.<DAETransform>();
		this.instance_cameras = new Vector.<DAEInstanceCamera>();
		this.instance_geometries = new Vector.<DAEInstanceGeometry>();
		
		for (i = 0; i < children.length(); i++)
		{
			var child:XML = children[i];
			var name:String = child.name().localName;
			
			switch (name)
			{
				case "node":
					this.nodes.push(new DAENode(this.parser, child));
					break;
				case "instance_camera":
					this.instance_cameras.push(new DAEInstanceCamera(child));
					break;
				case "instance_geometry":
					this.instance_geometries.push(new DAEInstanceGeometry(child));
					break;
				case "instance_node":
					instance = new DAEInstanceNode(child);
					instances = root.ns::library_nodes.ns::node.(@id == instance.url);
					if (instances.length())
						this.nodes.push(new DAENode(this.parser, instances[0]));
					break;
				case "matrix":
				case "translate":
				case "scale":
				case "rotate":
					this.transforms.push(new DAETransform(child));
					break;
				case "lookat":
				case "skew":
					break;
				default:
					trace(name);
					break;
			}
		}
	}
	
	public function get matrix() : Matrix3D
	{
		var matrix : Matrix3D = new Matrix3D();
		
		for (var i:int = 0; i < this.transforms.length; i++)
		{
			matrix.prepend(this.transforms[i].matrix);
		}
		
		return matrix;
	}
}

class DAEVisualScene extends DAENode
{
	public function DAEVisualScene(parser : DAEParser, element : XML = null)
	{
		super(parser, element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
	}
}

class DAEScene extends DAEElement
{
	public var instance_visual_scene : DAEInstanceVisualScene;
	public var instance_physics_scene : DAEInstancePhysicsScene;
	
	public function DAEScene(element : XML = null)
	{
		super(element);
	}
	
	/**
	 * @inheritDoc
	 */
	public override function deserialize(element : XML) : void
	{
		super.deserialize(element);
		
		var children:XMLList = element.children();
		var i:int;
		
		this.instance_visual_scene = null;
		this.instance_physics_scene = null;
		
		for (i = 0; i < children.length(); i++)
		{
			var child:XML = children[i];
			var name:String = child.name().localName;
			
			switch (name)
			{
				case "instance_visual_scene":
					this.instance_visual_scene = new DAEInstanceVisualScene(child);
					break;
				case "instance_physics_scene":
					this.instance_physics_scene = new DAEInstancePhysicsScene(child);
					break;
				default:
					break;
			}
		}
	}
}

class DAEParserState
{
	public static const LOAD_XML : uint = 0;
	public static const PARSE_IMAGES : uint = 1;
	public static const PARSE_MATERIALS : uint = 2;
	public static const PARSE_GEOMETRIES : uint = 3;
	public static const PARSE_VISUAL_SCENE : uint = 4;
	public static const PARSE_COMPLETE : uint = 5;
}
