package flixel.group;

import flixel.FlxBasic;
import flixel.FlxG;
import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import flixel.input.FlxPointer;
import flixel.math.FlxRandom;
import flixel.util.FlxArrayUtil;
import flixel.util.FlxSort;

typedef FlxGroup = FlxTypedGroup<FlxBasic>;

/**
 * This is an organizational class that can update and render a bunch of FlxBasics.
 * NOTE: Although FlxGroup extends FlxBasic, it will not automatically
 * add itself to the global collisions quad tree, it will only add its members.
 */
class FlxTypedGroup<T:FlxBasic> extends FlxBasic
{
	/**
	 * Helper function for overlap functions in FlxObject and FlxTilemap.
	 */
	@:allow(flixel.FlxObject)
	@:allow(flixel.tile.FlxTilemap)
	private static inline function overlaps(Callback:FlxBasic->Float->Float->Bool->FlxCamera->Bool, 
		Group:FlxTypedGroup<FlxBasic>, X:Float, Y:Float, InScreenSpace:Bool, Camera:FlxCamera):Bool
	{
		var result:Bool = false;
		if (Group != null)
		{
			var i = 0;
			var l = Group.length;
			var basic:FlxBasic;
			
			while (i < l)
			{
				basic = cast Group.members[i++];
				
				if (basic != null && Callback(basic, X, Y, InScreenSpace, Camera))
				{
					result = true;
					break;
				}
			}
		}
		return result;
	}
	
	@:allow(flixel.FlxObject)
	@:allow(flixel.tile.FlxTilemap)
	@:allow(flixel.system.FlxQuadTree)
	@:allow(flixel.input.FlxPointer)
	private static inline function resolveGroup(ObjectOrGroup:FlxBasic):FlxTypedGroup<FlxBasic>
	{
		var group:FlxTypedGroup<FlxBasic> = null;
		if ((ObjectOrGroup.flixelType == SPRITEGROUP) || 
		    (ObjectOrGroup.flixelType == GROUP))
		{
			if (ObjectOrGroup.flixelType == GROUP)
			{
				group = cast ObjectOrGroup;
			}
			else if (ObjectOrGroup.flixelType == SPRITEGROUP)
			{
				group = cast cast(ObjectOrGroup, FlxTypedSpriteGroup<Dynamic>).group;
			}
		}
		return group;
	}
	
	/**
	 * Array of all the members in this group.
	 */
	public var members(default, null):Array<T>;
	/**
	 * The maximum capacity of this group. Default is 0, meaning no max capacity, and the group can just grow.
	 */
	public var maxSize(default, set):Int;
	/**
	 * The number of entries in the members array. For performance and safety you should check this 
	 * variable instead of members.length unless you really know what you're doing!
	 */
	public var length(default, null):Int = 0;
	/**
	 * Internal helper variable for recycling objects a la FlxEmitter.
	 */
	private var _marker:Int = 0;
	
	/**
	 * @param	MaxSize		Maximum amount of members allowed
	 */
	public function new(MaxSize:Int = 0)
	{
		super();
		
		members = [];
		
		maxSize = Std.int(Math.abs(MaxSize));
		
		flixelType = GROUP;
	}
	
	/**
	 * WARNING: This will remove this group entirely. Use kill() if you want to disable it
	 * temporarily only and be able to revive() it later.
	 * Override this function to handle any deleting or "shutdown" type operations you might need,
	 * such as removing traditional Flash children like Sprite objects.
	 */
	override public function destroy():Void
	{
		super.destroy();
		
		if (members != null)
		{
			var i:Int = 0;
			var basic:FlxBasic = null;
			
			while (i < length)
			{
				basic = members[i++];
				
				if (basic != null)
					basic.destroy();
			}
			
			members = null;
		}
	}
	
	/**
	 * Automatically goes through and calls update on everything you added.
	 */
	override public function update():Void
	{
		var i:Int = 0;
		var basic:FlxBasic = null;
		
		while (i < length)
		{
			basic = members[i++];
			
			if (basic != null && basic.exists && basic.active)
			{
				basic.update();
			}
		}
	}
	
	/**
	 * Automatically goes through and calls render on everything you added.
	 */
	override public function draw():Void
	{
		var i:Int = 0;
		var basic:FlxBasic = null;
		
		while (i < length)
		{
			basic = members[i++];
			
			if (basic != null && basic.exists && basic.visible)
			{
				basic.draw();
			}
		}
	}
	
	/**
	 * Adds a new FlxBasic subclass (FlxBasic, FlxSprite, Enemy, etc) to the group.
	 * FlxGroup will try to replace a null member of the array first.
	 * Failing that, FlxGroup will add it to the end of the member array,
	 * assuming there is room for it, and doubling the size of the array if necessary.
	 * WARNING: If the group has a maxSize that has already been met,
	 * the object will NOT be added to the group!
	 * 
	 * @param	Object		The object you want to add to the group.
	 * @return	The same FlxBasic object that was passed in.
	 */
	public function add(Object:T):T
	{
		if (Object == null)
		{
			FlxG.log.warn("Cannot add a `null` object to a FlxGroup.");
			return null;
		}
		
		// Don't bother adding an object twice.
		if (members.indexOf(Object) >= 0)
		{
			return Object;
		}
		
		// First, look for a null entry where we can add the object.
		var index:Int = getFirstNull();
		if (index != -1)
		{
			members[index] = Object;
			
			if (index >= length)
			{
				length = index + 1;
			}
			
			return Object;
		}
		
		// If the group is full, return the Object
		if (maxSize > 0 && length >= maxSize)
		{
			return Object;
		}
		
		// If we made it this far, we need to add the object to the group.
		members.push(Object);
		length++;
		
		return Object;
	}
	
	/**
	 * Recycling is designed to help you reuse game objects without always re-allocating or "newing" them.
	 * It behaves differently depending on whether maxSize equals 0 or is bigger than 0.
	 * 
	 * maxSize > 0 / "rotating-recycling" (used by FlxEmitter):
	 *   - at capacity:  returns the next object in line, no matter its properties like alive, exists etc.
	 *   - otherwise:    returns a new object.
	 * 
	 * maxSize == 0 / "grow-style-recycling"
	 *   - tries to find the first object with exists == false
	 *   - otherwise: adds a new object to the members array
	 *
	 * WARNING: If this function needs to create a new object, and no object class was provided, 
	 * it will return null instead of a valid object!
	 * 
	 * @param   ObjectClass     The class type you want to recycle (e.g. FlxSprite, EvilRobot, etc).
	 * @param   ObjectFactory   Optional factory function to create a new object if there aren't any dead members to recycle.
	 *                          If null, Type.createInstance() is used which requires the class to have no constructor parameters.
	 * @param   Force           Force the object to be an ObjectClass and not a super class of ObjectClass. 
	 * @param   Revive          Whether recycled members should automatically be revived (by calling revive() on them)
	 * @return  A reference to the object that was created.
	 */
	public function recycle(?ObjectClass:Class<T>, ?ObjectFactory:Void->T, Force:Bool = false, Revive:Bool = true):T
	{
		var basic:FlxBasic = null;
		
		// roatated recycling
		if (maxSize > 0)
		{
			// create new instance
			if (length < maxSize)
			{
				return add(recycleCreateObject(ObjectClass, ObjectFactory));
			}
			// get the next member if at capacity
			else
			{
				basic = members[_marker++];
				
				if (_marker >= maxSize)
				{
					_marker = 0;
				}
				
				if (Revive)
				{
					basic.revive();
				}
				
				return cast basic;
			}
		}
		// grow-style recycling - grab a basic with exists == false or create a new one
		else
		{
			basic = getFirstAvailable(ObjectClass, Force);
			
			if (basic != null)
			{
				if (Revive)
				{
					basic.revive();
				}
				return cast basic;
			}
			
			return add(recycleCreateObject(ObjectClass, ObjectFactory));
		}
	}
	
	private inline function recycleCreateObject(?ObjectClass:Class<T>, ?ObjectFactory:Void->T):T
	{
		var object:T = null;
		
		if (ObjectFactory != null)
		{
			object = ObjectFactory();
		}
		else if (ObjectClass != null)
		{
			object = Type.createInstance(ObjectClass, []); 
		}
		
		return object;
	}
	
	/**
	 * Removes an object from the group.
	 * 
	 * @param	Object	The FlxBasic you want to remove.
	 * @param	Splice	Whether the object should be cut from the array entirely or not.
	 * @return	The removed object.
	 */
	public function remove(Object:T, Splice:Bool = false):T
	{
		if (members == null)
			return null;
		
		var index:Int = members.indexOf(Object);
		
		if (index < 0)
			return null;
		
		if (Splice)
			members.splice(index, 1);
		else
			members[index] = null;
		
		return Object;
	}
	
	/**
	 * Replaces an existing FlxBasic with a new one. 
	 * Does not do anything and returns null if the old object is not part of the group.
	 * 
	 * @param	OldObject	The object you want to replace.
	 * @param	NewObject	The new object you want to use instead.
	 * @return	The new object.
	 */
	public function replace(OldObject:T, NewObject:T):T
	{
		var index:Int = members.indexOf(OldObject);
		
		if (index < 0)
			return null;
		
		members[index] = NewObject;
		
		return NewObject;
	}
	
	/**
	 * Call this function to sort the group according to a particular value and order. For example, to sort game objects for Zelda-style 
	 * overlaps you might call myGroup.sort(FlxSort.byY, FlxSort.ASCENDING) at the bottom of your FlxState.update() override.
	 * 
	 * @param	Function	The sorting function to use - you can use one of the premade ones in FlxSort or write your own using FlxSort.byValues() as a backend
	 * @param	Order		A FlxGroup constant that defines the sort order.  Possible values are FlxSort.ASCENDING (default) and FlxSort.DESCENDING. 
	 */
	public inline function sort(Function:Int->T->T->Int, Order:Int = FlxSort.ASCENDING):Void
	{
		members.sort(Function.bind(Order));
	}
	
	/**
	 * Call this function to retrieve the first object with exists == false in the group.
	 * This is handy for recycling in general, e.g. respawning enemies.
	 * 
	 * @param	ObjectClass		An optional parameter that lets you narrow the results to instances of this particular class.
	 * @param 	Force           Force the object to be an ObjectClass and not a super class of ObjectClass. 
	 * @return	A FlxBasic currently flagged as not existing.
	 */
	public function getFirstAvailable(?ObjectClass:Class<T>, Force:Bool = false):T
	{
		var i:Int = 0;
		var basic:FlxBasic = null;
		
		while (i < length)
		{
			basic = members[i++]; // we use basic as FlxBasic for performance reasons
			
			if ((basic != null) && !basic.exists && ((ObjectClass == null) || Std.is(basic, ObjectClass)))
			{
				if (Force && Type.getClassName(Type.getClass(basic)) != Type.getClassName(ObjectClass)) 
				{
					continue;
				}
				return members[i - 1];
			}
		}
		
		return null;
	}
	
	/**
	 * Call this function to retrieve the first index set to 'null'.
	 * Returns -1 if no index stores a null object.
	 * 
	 * @return	An Int indicating the first null slot in the group.
	 */
	public function getFirstNull():Int
	{
		var i:Int = 0;
		
		while (i < length)
		{
			if (members[i] == null)
			{
				return i;
			}
			i++;
		}
		
		return -1;
	}
	
	/**
	 * Call this function to retrieve the first object with exists == true in the group.
	 * This is handy for checking if everything's wiped out, or choosing a squad leader, etc.
	 * 
	 * @return	A FlxBasic currently flagged as existing.
	 */
	public function getFirstExisting():T
	{
		var i:Int = 0;
		var basic:FlxBasic = null;
		
		while (i < length)
		{
			basic = members[i++];
			
			if (basic != null && basic.exists)
			{
				return cast basic;
			}
		}
		
		return null;
	}
	
	/**
	 * Call this function to retrieve the first object with dead == false in the group.
	 * This is handy for checking if everything's wiped out, or choosing a squad leader, etc.
	 * 
	 * @return	A FlxBasic currently flagged as not dead.
	 */
	public function getFirstAlive():T
	{
		var i:Int = 0;
		var basic:FlxBasic = null;
		
		while (i < length)
		{
			basic = members[i++]; // we use basic as FlxBasic for performance reasons
			
			if (basic != null && basic.exists && basic.alive)
			{
				return cast basic;
			}
		}
		
		return null;
	}
	
	/**
	 * Call this function to retrieve the first object with dead == true in the group.
	 * This is handy for checking if everything's wiped out, or choosing a squad leader, etc.
	 * 
	 * @return	A FlxBasic currently flagged as dead.
	 */
	public function getFirstDead():T
	{
		var i:Int = 0;
		var basic:FlxBasic = null;
		
		while (i < length)
		{
			basic = members[i++]; // we use basic as FlxBasic for performance reasons
			
			if (basic != null && !basic.alive)
			{
				return cast basic;
			}
		}
		
		return null;
	}
	
	/**
	 * Call this function to find out how many members of the group are not dead.
	 * 
	 * @return	The number of FlxBasics flagged as not dead.  Returns -1 if group is empty.
	 */
	public function countLiving():Int
	{
		var i:Int = 0;
		var count:Int = -1;
		var basic:FlxBasic = null;
		
		while (i < length)
		{
			basic = members[i++];
			
			if (basic != null)
			{
				if (count < 0)
				{
					count = 0;
				}
				if (basic.exists && basic.alive)
				{
					count++;
				}
			}
		}
		
		return count;
	}
	
	/**
	 * Call this function to find out how many members of the group are dead.
	 * 
	 * @return	The number of FlxBasics flagged as dead.  Returns -1 if group is empty.
	 */
	public function countDead():Int
	{
		var i:Int = 0;
		var count:Int = -1;
		var basic:FlxBasic = null;
		
		while (i < length)
		{
			basic = members[i++];
			
			if (basic != null)
			{
				if (count < 0)
				{
					count = 0;
				}
				if (!basic.alive)
				{
					count++;
				}
			}
		}
		
		return count;
	}
	
	/**
	 * Returns a member at random from the group.
	 * 
	 * @param	StartIndex	Optional offset off the front of the array. Default value is 0, or the beginning of the array.
	 * @param	Length		Optional restriction on the number of values you want to randomly select from.
	 * @return	A FlxBasic from the members list.
	 */
	public function getRandom(StartIndex:Int = 0, Length:Int = 0):T
	{
		if (StartIndex < 0)
		{
			StartIndex = 0;
		}
		if (Length <= 0)
		{
			Length = length;
		}
		
		return FlxRandom.getObject(members, StartIndex, Length);
	}
	
	/**
	 * Remove all instances of FlxBasic subclass (FlxSprite, FlxBlock, etc) from the list.
	 * WARNING: does not destroy() or kill() any of these objects!
	 */
	public function clear():Void
	{
		length = 0;
		FlxArrayUtil.clearArray(members);
	}
	
	/**
	 * Calls kill on the group's members and then on the group itself. 
	 * You can revive this group later via revive() after this.
	 */
	override public function kill():Void
	{
		var i:Int = 0;
		var basic:FlxBasic = null;
		
		while (i < length)
		{
			basic = members[i++];
			
			if (basic != null && basic.exists)
			{
				basic.kill();
			}
		}
		
		super.kill();
	}
	
	/**
	 * Iterate through every member
	 */
	public inline function iterator(?filter:T->Bool):FlxTypedGroupIterator<T>
	{
		return new FlxTypedGroupIterator<T>(members, filter);
	}
	
	/**
	 * Applies a function to all members
	 * 
	 * @param   Function   A function that modifies one element at a time
	 * @param   Recurse    Whether or not to apply the function to members of subgroups as well
	 */
	public function forEach(Function:T->Void, Recurse:Bool = false)
	{
		var i:Int = 0;
		var basic:FlxBasic = null;
		
		while (i < length)
		{
			basic = members[i++];
			
			if (basic != null)
			{
				if (Recurse)
				{
					var group = resolveGroup(basic);
					if (group != null)
					{
						group.forEach(cast Function, Recurse);
					}
				}
				
				Function(cast basic);
			}
		}
	}
	
	/**
	 * Applies a function to all alive members
	 * 
	 * @param   Function   A function that modifies one element at a time
	 * @param   Recurse    Whether or not to apply the function to members of subgroups as well
	 */
	public function forEachAlive(Function:T->Void, Recurse:Bool = false)
	{
		var i:Int = 0;
		var basic:FlxBasic = null;
		
		while (i < length)
		{
			basic = members[i++];
			
			if (basic != null && basic.exists && basic.alive)
			{
				if (Recurse)
				{
					var group = resolveGroup(basic);
					if (group != null)
					{
						group.forEachAlive(cast Function, Recurse);
					}
				}
				
				Function(cast basic);
			}
		}
	}

	/**
	 * Applies a function to all dead members
	 * 
	 * @param   Function   A function that modifies one element at a time
	 * @param   Recurse    Whether or not to apply the function to members of subgroups as well
	 */
	public function forEachDead(Function:T->Void, Recurse:Bool = false)
	{
		var i:Int = 0;
		var basic:FlxBasic = null;
		
		while (i < length)
		{
			basic = members[i++];
			
			if (basic != null && !basic.alive)
			{
				if (Recurse)
				{
					var group = resolveGroup(basic);
					if (group != null)
					{
						group.forEachDead(cast Function, Recurse);
					}
				}
				
				Function(cast basic);
			}
		}
	}

	/**
	 * Applies a function to all existing members
	 * 
	 * @param   Function   A function that modifies one element at a time
	 * @param   Recurse    Whether or not to apply the function to members of subgroups as well
	 */
	public function forEachExists(Function:T->Void, Recurse:Bool = false)
	{
		var i:Int = 0;
		var basic:FlxBasic = null;
		
		while (i < length)
		{
			basic = members[i++];
			
			if (basic != null && basic.exists)
			{
				if (Recurse)
				{
					var group = resolveGroup(basic);
					if (group != null)
					{
						group.forEachExists(cast Function, Recurse);
					}
				}
				
				Function(cast basic);
			}
		}
	}
	
	/**
	 * Applies a function to all members of type Class<K>
	 * 
	 * @param   ObjectClass   A class that objects will be checked against before Function is applied, ex: FlxSprite
	 * @param   Function      A function that modifies one element at a time
	 * @param   Recurse       Whether or not to apply the function to members of subgroups as well 
	 */
	public function forEachOfType<K>(ObjectClass:Class<K>, Function:K->Void, Recurse:Bool = false)
	{
		var i:Int = 0;
		var basic:FlxBasic = null;
		
		while (i < length)
		{
			basic = members[i++];
			
			if (basic != null &&  Std.is(basic, ObjectClass))
			{
				if (Recurse)
				{
					var group = resolveGroup(basic);
					if (group != null)
					{
						group.forEachOfType(ObjectClass, cast Function, Recurse);
					}
				}
				
				Function(cast basic);
			}
		}
	}
	
	private function set_maxSize(Size:Int):Int
	{
		maxSize = Std.int(Math.abs(Size));
		
		if (_marker >= maxSize)
		{
			_marker = 0;
		}
		if (maxSize == 0 || members == null || maxSize >= length)
		{
			return maxSize;
		}
		
		// If the max size has shrunk, we need to get rid of some objects
		var i:Int = maxSize;
		var l:Int = length;
		var basic:FlxBasic = null;
		
		while (i < l)
		{
			basic = members[i++];
			
			if (basic != null)
				basic.destroy();
		}
		
		FlxArrayUtil.setLength(members, maxSize);
		length = members.length;
		
		return maxSize;
	}
}

/**
 * Iterator implementation for groups
 * Support a filter method (used for iteratorAlive, iteratorDead and iteratorExists)
 * @author Masadow
 */
class FlxTypedGroupIterator<T>
{
	private var _groupMembers:Array<T>;
	private var _filter:T->Bool;
	private var _cursor:Int;
	private var _length:Int;

	public function new(GroupMembers:Array<T>, ?filter:T->Bool)
	{
		_groupMembers = GroupMembers;
		_filter = filter;
		_cursor = 0;
		_length = _groupMembers.length;
	}

	public function next()
	{
		return hasNext() ? _groupMembers[_cursor++] : null;
	}

	public function hasNext():Bool
	{
		while (_cursor < _length && (_groupMembers[_cursor] == null || _filter != null && !_filter(_groupMembers[_cursor])))
		{
			_cursor++;
		}
		return _cursor < _length;
	}
}
